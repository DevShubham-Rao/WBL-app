import SwiftUI
import CoreLocation

struct PlanView: View {
    @EnvironmentObject var store: VisitStore
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var location = LocationService()
    @State private var selected = Set<UUID>()
    @State private var selectedTypes: [UUID: VisitKind] = [:]
    @State private var date = Date()
    @State private var roundTrip = true
    @State private var startAddress = ""
    @State private var useLocation = true
    @State private var busy = false

    var inPersonCount: Int { selected.filter { (selectedTypes[$0] ?? .inPerson) == .inPerson }.count }
    var remoteCount: Int { selected.count - inPersonCount }
    var body: some View {
        NavigationStack {
            Form {
                if store.activeTrip != nil {
                    Section { Label("Finish your active trip on the Home tab before starting another.",systemImage:"exclamationmark.circle").foregroundStyle(.orange) }
                }
                Section("Schedule") {
                    DatePicker("Visit date",selection:$date,displayedComponents:.date)
                    if inPersonCount > 0 { Toggle("Round trip to starting point",isOn:$roundTrip) }
                }
                if inPersonCount > 0 {
                    Section("Starting point (in-person visits only)") {
                        Toggle("Use current location",isOn:$useLocation)
                        if useLocation {
                            Text(location.coordinate == nil ? "Location not yet available. Allow permission when prompted." : "Current GPS location ready")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Refresh location") { location.request() }
                        } else {
                            TextField("Starting street address",text:$startAddress,axis:.vertical)
                                .textInputAutocapitalization(.words)
                        }
                    }
                }
                Section("Choose students • \(selected.count) selected") {
                    ForEach(store.db.students.sorted { $0.lastName.localizedStandardCompare($1.lastName) == .orderedAscending }) { s in
                        VStack(alignment:.leading,spacing:8) {
                            Button {
                                if selected.contains(s.id) { selected.remove(s.id) }
                                else { selected.insert(s.id); if selectedTypes[s.id] == nil { selectedTypes[s.id] = .inPerson } }
                            } label: {
                                HStack(spacing:12) {
                                    Image(systemName:selected.contains(s.id) ? "checkmark.circle.fill":"circle")
                                        .foregroundStyle(selected.contains(s.id) ? theme.current.palette.tint : .secondary)
                                    VStack(alignment:.leading,spacing:3) {
                                        Text(s.fullName).foregroundStyle(.primary).font(.headline)
                                        Text("\(s.employer) • \(s.visitCount) recorded visits")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            if selected.contains(s.id) {
                                Picker("Visit type", selection:Binding(
                                    get: { selectedTypes[s.id] ?? .inPerson },
                                    set: { selectedTypes[s.id] = $0 }
                                )) {
                                    ForEach(VisitKind.allCases) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }.pickerStyle(.menu)
                                if selectedTypes[s.id] == .inPerson {
                                    Text(s.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical,3)
                    }
                }
                Section("Route preview") {
                    Label("\(inPersonCount) in-person visits will appear on the route map",systemImage:"map")
                    Label("\(remoteCount) Zoom, phone or message contacts won't appear on the map",systemImage:"video")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button {
                        Task { await createTrip() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() }
                            else { Label(inPersonCount == 0 ? "Start Contact Session" : "Optimize Route & Start",systemImage:"arrow.triangle.turn.up.right.diamond.fill") }
                            Spacer()
                        }
                    }.disabled(busy || selected.isEmpty || store.activeTrip != nil)
                }
                Section {
                    Text("Only in-person visits affect the driving route or reimbursement miles. The driving estimate uses Apple Maps and isn't actual GPS mileage. Zoom, phone and message visits still count toward each student's history.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Plan visits")
            .onAppear { if inPersonCount > 0 && useLocation { location.request() } }
            .onChange(of:inPersonCount) { _, number in
                if number > 0 && useLocation && location.coordinate == nil { location.request() }
            }
        }
    }

    func createTrip() async {
        busy = true
        defer { busy = false }
        do {
            let chosen = store.db.students.filter { selected.contains($0.id) }
            let inPerson = chosen.filter { (selectedTypes[$0.id] ?? .inPerson) == .inPerson }
            let remote = chosen.filter { (selectedTypes[$0.id] ?? .inPerson) != .inPerson }
                .sorted { $0.lastName.localizedStandardCompare($1.lastName) == .orderedAscending }
            var orderedStops: [TripStop] = []
            var originName = ""
            var estimatedMiles: Double? = nil
            if !inPerson.isEmpty {
                let origin: CLLocationCoordinate2D
                if useLocation {
                    guard let point = location.coordinate else { throw RouteError.noLocation }
                    origin = point
                    originName = "\(point.latitude),\(point.longitude)"
                } else {
                    guard !startAddress.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw RouteError.noLocation }
                    origin = try await RouteService.geocode(startAddress)
                    originName = startAddress
                }
                let route = try await RouteService.plan(start:origin,originName:originName,students:inPerson,roundTrip:roundTrip)
                estimatedMiles = route.estimatedMiles
                originName = route.originName
                orderedStops = route.orderedIDs.map { TripStop(studentID:$0,kind:.inPerson) }
            }
            for s in remote { orderedStops.append(TripStop(studentID:s.id,kind:selectedTypes[s.id] ?? .phoneCall)) }
            let trip = Trip(date:date,startAddress:originName,stops:orderedStops,
                            roundTrip:!inPerson.isEmpty && roundTrip,estimatedMiles:estimatedMiles)
            store.db.trips.insert(trip,at:0)
            selected = []
            selectedTypes = [:]
        } catch { store.errorMessage = error.localizedDescription }
    }
}

struct TripCard: View {
    @EnvironmentObject var store: VisitStore
    @EnvironmentObject var theme: ThemeManager
    let trip: Trip
    @State private var finalMileage = ""
    @State private var confirmFinish = false
    var physicalAddresses: [String] {
        trip.stops.filter { $0.visitKind == .inPerson }
            .compactMap { store.student($0.studentID)?.address }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {
                Image(systemName:"calendar.badge.clock").foregroundStyle(theme.current.palette.tint)
                Text(trip.date.formatted(date:.abbreviated,time:.omitted)).font(.headline)
                Spacer()
                Text("\(trip.stops.filter{$0.arrival != nil}.count)/\(trip.stops.count) completed")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(trip.stops.indices, id:\.self) { idx in
                let stop = trip.stops[idx]
                if let s = store.student(stop.studentID) {
                    VStack(alignment:.leading,spacing:7) {
                        HStack {
                            Text("\(idx + 1). \(s.fullName)").font(.headline)
                            Spacer()
                            if stop.arrival != nil { Label("Done",systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                        }
                        Label(stop.visitKind.rawValue,systemImage:stop.visitKind.symbol)
                            .font(.subheadline).foregroundStyle(theme.current.palette.tint)
                        Text(s.employer).font(.subheadline)
                        if stop.visitKind == .inPerson {
                            Text(s.address).font(.caption).foregroundStyle(.secondary)
                        }
                        if let arrival = stop.arrival {
                            Text("Recorded: \(arrival.formatted(date:.abbreviated,time:.standard))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(stop.visitKind == .inPerson ? "I Have Visited" : "Mark Contact Complete",systemImage:"checkmark.circle") {
                                store.visit(tripID:trip.id,stopID:stop.id)
                            }.buttonStyle(.borderedProminent)
                        }
                        NavigationLink("Student history & notes") { StudentDetailView(studentID:s.id) }.font(.caption)
                    }.padding().frame(maxWidth:.infinity,alignment:.leading)
                        .background(.background,in:RoundedRectangle(cornerRadius:12))
                }
            }
            if trip.inPersonStops.count > 0 {
                if let miles = trip.estimatedMiles {
                    Label(String(format:"Estimated travel: %.1f miles",miles),systemImage:"point.bottomleft.forward.to.point.topright.scurvepath")
                        .font(.subheadline)
                }
                if let url = RouteService.googleURL(origin:trip.startAddress,addresses:physicalAddresses,roundTrip:trip.roundTrip) {
                    Link(destination:url) { Label("Open in-person route in Google Maps",systemImage:"map") }
                        .buttonStyle(.borderedProminent)
                }
                if let first = physicalAddresses.first,
                   let url = RouteService.appleURL(start:trip.startAddress,destination:first) {
                    Link("Navigate first in-person stop in Apple Maps",destination:url).font(.subheadline)
                }
                TextField("Actual trip mileage (optional)",text:$finalMileage)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            } else {
                Label("Remote-only session: no route or mileage",systemImage:"video")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button("Finish & Save",role:.none) { confirmFinish = true }
                .buttonStyle(.bordered)
                .confirmationDialog("Finish this session?",isPresented:$confirmFinish) {
                    Button("Finish and save") {
                        var changed = trip
                        if trip.inPersonStops.count > 0 {
                            let parsed = Double(finalMileage)
                            changed.finalMiles = (parsed != nil && parsed! >= 0) ? parsed : trip.estimatedMiles
                        } else { changed.finalMiles = nil }
                        changed.completed = .now
                        store.updateTrip(changed)
                    }
                } message: {
                    Text("All completed contacts and timestamps remain saved. Unmarked contacts won't be counted.")
                }
        }.padding().background(theme.current.palette.cardBackground,in:RoundedRectangle(cornerRadius:18))
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: VisitStore
    var finished: [Trip] { store.db.trips.filter { $0.completed != nil }.sorted { $0.date > $1.date } }
    var total: Double { finished.reduce(0) { $0 + ($1.finalMiles ?? 0) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading) {
                        Text("All-time recorded mileage").font(.subheadline).foregroundStyle(.secondary)
                        Text(String(format:"%.1f miles",total)).font(.largeTitle.bold())
                        Text("To export a specific date range, use Data → Export reports.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Saved trips and contact sessions") {
                    if finished.isEmpty { Text("No completed sessions yet").foregroundStyle(.secondary) }
                    ForEach(finished) { t in
                        NavigationLink { TripHistoryDetail(tripID:t.id) } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text(t.date.formatted(date:.abbreviated,time:.omitted)).font(.headline)
                                Text("\(t.stops.count) contacts • \(t.inPersonStops.count) in person • " +
                                     (t.inPersonStops.isEmpty ? "No travel" : String(format:"%.1f miles",t.finalMiles ?? 0)))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.navigationTitle("Visit & mileage log")
        }
    }
}

struct TripHistoryDetail: View {
    @EnvironmentObject var store: VisitStore
    let tripID: UUID
    @State private var editingMileage = ""
    var trip: Trip? { store.db.trips.first { $0.id == tripID } }
    var body: some View {
        Form {
            if let t = trip {
                Section("Trip") {
                    LabeledContent("Scheduled date",value:t.date.formatted(date:.abbreviated,time:.omitted))
                    LabeledContent("In-person visits",value:"\(t.inPersonStops.count)")
                    if !t.inPersonStops.isEmpty {
                        LabeledContent("Round trip",value:t.roundTrip ? "Yes":"No")
                        LabeledContent("Estimate",value:String(format:"%.2f miles",t.estimatedMiles ?? 0))
                        LabeledContent("Saved miles",value:String(format:"%.2f miles",t.finalMiles ?? 0))
                        TextField("Correct reimbursement miles",text:$editingMileage).keyboardType(.decimalPad)
                        Button("Update saved miles") {
                            guard let value = Double(editingMileage), value >= 0 else {
                                store.errorMessage = "Enter a valid nonnegative number."
                                return
                            }
                            var changed = t
                            changed.finalMiles = value
                            store.updateTrip(changed)
                            editingMileage = ""
                        }
                    } else { Text("Remote session — no mileage").foregroundStyle(.secondary) }
                }
                Section("Contacts") {
                    ForEach(t.stops) { stop in
                        if let s = store.student(stop.studentID) {
                            VStack(alignment:.leading,spacing:5) {
                                Text(s.fullName)
                                Label(stop.visitKind.rawValue,systemImage:stop.visitKind.symbol).font(.caption)
                                Text(stop.arrival?.formatted(date:.abbreviated,time:.standard) ?? "Not marked complete")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Session details")
    }
}
