import SwiftUI
import CoreLocation

struct PlanView: View {
    @EnvironmentObject var store: VisitStore
    @StateObject private var location = LocationService()
    @State private var selected = Set<UUID>()
    @State private var date = Date()
    @State private var roundTrip = true
    @State private var startAddress = ""
    @State private var useLocation = true
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                if store.activeTrip != nil { Section { Label("Finish your active trip on the Home tab before starting another.",systemImage:"exclamationmark.circle").foregroundStyle(.orange) } }
                Section("Schedule") { DatePicker("Visit date",selection:$date,displayedComponents:.date); Toggle("Round trip to starting point",isOn:$roundTrip) }
                Section("Starting point") {
                    Toggle("Use current location",isOn:$useLocation)
                    if useLocation { Text(location.coordinate == nil ? "Location not yet available. Allow permission when prompted." : "Current GPS location ready").font(.caption).foregroundStyle(.secondary); Button("Refresh location") {location.request()} }
                    else { TextField("Starting street address",text:$startAddress,axis:.vertical).textInputAutocapitalization(.words) }
                }
                Section("Choose students • \(selected.count) selected") {
                    ForEach(store.db.students.sorted { $0.lastName < $1.lastName }) { s in
                        Button { if selected.contains(s.id) {selected.remove(s.id)} else {selected.insert(s.id)} } label: {
                            HStack { Image(systemName:selected.contains(s.id) ? "checkmark.circle.fill":"circle").foregroundStyle(selected.contains(s.id) ? .indigo : .secondary)
                                VStack(alignment:.leading) {Text(s.fullName).foregroundStyle(.primary); Text(s.employer + " • " + s.address).font(.caption).foregroundStyle(.secondary) };Spacer() }
                        }
                    }
                }
                Section {
                    Button { Task { await createTrip() } } label: { HStack {Spacer(); if busy {ProgressView()} else {Label("Optimize & Start Trip",systemImage:"arrow.triangle.turn.up.right.diamond.fill")};Spacer()} }
                        .disabled(busy || selected.isEmpty || store.activeTrip != nil)
                }
                Section { Text("Travel miles are an Apple Maps driving-distance estimate. The stop order uses a geographic heuristic, not real-time traffic optimization. Your actual final mileage can be entered at the end of the trip.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Plan visits")
            .onAppear {location.request()}
        }
    }
    func createTrip() async {
        busy = true; defer {busy=false}
        do {
            let origin: CLLocationCoordinate2D
            let label: String
            if useLocation {
                guard let point = location.coordinate else {throw RouteError.noLocation}
                origin=point; label="\(point.latitude),\(point.longitude)"
            } else {
                guard !startAddress.trimmingCharacters(in:.whitespaces).isEmpty else {throw RouteError.noLocation}
                origin=try await RouteService.geocode(startAddress);label=startAddress
            }
            let chosen=store.db.students.filter {selected.contains($0.id)}
            let route=try await RouteService.plan(start:origin,originName:label,students:chosen,roundTrip:roundTrip)
            let trip=Trip(date:date,startAddress:route.originName,stops:route.orderedIDs.map{TripStop(studentID:$0)},roundTrip:roundTrip,estimatedMiles:route.estimatedMiles)
            store.db.trips.insert(trip,at:0);selected=[]
        } catch { store.errorMessage=error.localizedDescription }
    }
}
struct TripCard: View {
    @EnvironmentObject var store: VisitStore
    let trip: Trip
    @State private var finalMileage = ""
    @State private var confirmFinish = false
    var addresses: [String] {trip.stops.compactMap{store.student($0.studentID)?.address}}
    var body: some View {
        VStack(alignment:.leading,spacing:15) {
            HStack { Image(systemName:"car.side.fill").foregroundStyle(.indigo);Text(trip.date.formatted(date:.abbreviated,time:.omitted)).font(.headline);Spacer();Text("\(trip.stops.filter{$0.arrival != nil}.count)/\(trip.stops.count) visited").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(trip.stops.indices, id:\.self) { idx in
                let stop = trip.stops[idx]
                if let s=store.student(stop.studentID) {
                    VStack(alignment:.leading,spacing:6) {
                        HStack { Text("\(idx+1). \(s.fullName)").font(.headline);Spacer();if stop.arrival != nil {Label("Done",systemImage:"checkmark.circle.fill").foregroundStyle(.green).font(.caption)} }
                        Text(s.employer).font(.subheadline)
                        Text(s.address).font(.caption).foregroundStyle(.secondary)
                        if let arrival=stop.arrival {Text("Visited: \(arrival.formatted(date:.abbreviated,time:.standard))").font(.caption).foregroundStyle(.secondary)}
                        else { Button("I Have Visited",systemImage:"checkmark.circle") {store.visit(tripID:trip.id,stopID:stop.id)}.buttonStyle(.borderedProminent) }
                        NavigationLink("Student notes & details") {StudentDetailView(studentID:s.id)}.font(.caption)
                    }.padding().frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:12))
                }
            }
            if let miles=trip.estimatedMiles { Label(String(format:"Estimated round/one-way route: %.1f miles",miles),systemImage:"point.bottomleft.forward.to.point.topright.scurvepath").font(.subheadline) }
            if let url=RouteService.googleURL(origin:trip.startAddress,addresses:addresses,roundTrip:trip.roundTrip) {
                Link(destination:url) {Label("Open full route in Google Maps",systemImage:"map")}.buttonStyle(.borderedProminent)
            }
            // Apple Maps only supports individual point-to-point legs via public URL scheme.
            if let first=addresses.first,let url=RouteService.appleURL(start:trip.startAddress,destination:first) {
                Link("Navigate first stop in Apple Maps",destination:url).font(.subheadline)
            }
            TextField("Final mileage (optional; actual miles)",text:$finalMileage).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
            Button("Finish & Save Trip",role:.none) {confirmFinish=true}.buttonStyle(.bordered)
                .confirmationDialog("Finish this trip?",isPresented:$confirmFinish) {
                    Button("Finish and save") {
                        var changed=trip
                        let parsed=Double(finalMileage)
                        changed.finalMiles=(parsed != nil && parsed! >= 0) ? parsed : trip.estimatedMiles
                        changed.completed = .now
                        store.updateTrip(changed)
                    }
                } message: {Text("Mileage and completed visit timestamps will be saved. Unvisited stops will remain unvisited.")}
        }.padding().background(Color.indigo.opacity(0.07),in:RoundedRectangle(cornerRadius:18))
    }
}
struct HistoryView: View {
    @EnvironmentObject var store: VisitStore
    var finished: [Trip] {store.db.trips.filter{$0.completed != nil}.sorted{$0.date > $1.date}}
    var total: Double {finished.reduce(0){$0 + ($1.finalMiles ?? 0)}}
    var csv: String {
        func esc(_ s:String)->String {"\"" + s.replacingOccurrences(of:"\"",with:"\"\"") + "\""}
        return (["Trip Date,Visit Stops,Round Trip,Estimated Miles,Reimbursement Miles,Completed"] + finished.map { t in
            [t.date.formatted(.iso8601.year().month().day()),t.stops.compactMap {store.student($0.studentID)?.fullName}.joined(separator:"; "),t.roundTrip ? "Yes":"No",String(format:"%.2f",t.estimatedMiles ?? 0),String(format:"%.2f",t.finalMiles ?? 0),t.completed?.formatted(.iso8601) ?? ""].map(esc).joined(separator:",")
        }).joined(separator:"\n")
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading) {Text("Total saved mileage").font(.subheadline).foregroundStyle(.secondary);Text(String(format:"%.1f miles",total)).font(.largeTitle.bold())}
                    ShareLink("Export mileage CSV",item:csv)
                }
                Section("Completed trips") {
                    ForEach(finished) {t in
                        NavigationLink {TripHistoryDetail(tripID:t.id)} label: {
                            VStack(alignment:.leading,spacing:5) {Text(t.date.formatted(date:.abbreviated,time:.omitted)).font(.headline);Text("\(t.stops.count) stops • \(String(format:"%.1f",t.finalMiles ?? 0)) miles").font(.subheadline).foregroundStyle(.secondary)}
                        }
                    }
                }
            }.navigationTitle("Mileage log")
        }
    }
}
struct TripHistoryDetail: View {
    @EnvironmentObject var store: VisitStore
    let tripID: UUID
    @State private var editingMileage = ""
    var trip:Trip? {store.db.trips.first{$0.id == tripID}}
    var body:some View {
        Form {
            if let t=trip {
                Section("Trip") {
                    LabeledContent("Visit date",value:t.date.formatted(date:.abbreviated,time:.omitted))
                    LabeledContent("Round trip",value:t.roundTrip ? "Yes":"No")
                    LabeledContent("Estimate",value:String(format:"%.2f miles",t.estimatedMiles ?? 0))
                    LabeledContent("Saved miles",value:String(format:"%.2f miles",t.finalMiles ?? 0))
                    TextField("Correct reimbursement miles",text:$editingMileage).keyboardType(.decimalPad)
                    Button("Update saved miles") {
                        guard let value=Double(editingMileage),value >= 0 else {store.errorMessage="Enter a valid nonnegative number.";return}
                        var changed=t;changed.finalMiles=value;store.updateTrip(changed);editingMileage=""
                    }
                }
                Section("Stops") {ForEach(t.stops) {stop in
                    if let s=store.student(stop.studentID) {VStack(alignment:.leading) {Text(s.fullName);Text(stop.arrival?.formatted(date:.abbreviated,time:.standard) ?? "Not marked visited").font(.caption).foregroundStyle(.secondary)}}
                }}
            }
        }.navigationTitle("Trip details")
    }
}
