import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

struct RootView: View {
    @EnvironmentObject var store: VisitStore
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Home",systemImage:"house.fill") }
            StudentsView().tabItem { Label("Students",systemImage:"person.2.fill") }
            PlanView().tabItem { Label("Plan",systemImage:"map.fill") }
            HistoryView().tabItem { Label("Mileage",systemImage:"car.fill") }
            DataView().tabItem { Label("Data",systemImage:"square.and.arrow.up") }
        }
        .tint(.indigo)
        .alert("Notice", isPresented: Binding(get:{store.errorMessage != nil},set:{if !$0 {store.errorMessage = nil}})) { Button("OK",role:.cancel) { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
    }
}
struct DashboardView: View {
    @EnvironmentObject var store: VisitStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack(spacing:12) {
                        summary("Students", "\(store.db.students.count)","person.2")
                        summary("Total visits", "\(store.db.students.reduce(0) { $0 + $1.visitCount })","number.circle")
                    }
                    if let trip = store.activeTrip {
                        Text("ACTIVE TRIP").font(.caption.bold()).foregroundStyle(.indigo)
                        TripCard(trip:trip)
                    } else {
                        ContentUnavailableView("No active trip",systemImage:"map",description:Text("Select students in the Plan tab to begin a workplace visit route."))
                    }
                }.padding()
            }.navigationTitle("WBL Visits")
        }
    }
    func summary(_ title:String,_ value:String,_ icon:String) -> some View {
        VStack(alignment:.leading,spacing:8) { Label(title,systemImage:icon).font(.subheadline).foregroundStyle(.secondary); Text(value).font(.largeTitle.bold()) }
            .frame(maxWidth:.infinity,alignment:.leading).padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
}
enum StudentSort: String, CaseIterable, Identifiable {
    case lastName = "Last name (A–Z)"
    case firstName = "First name (A–Z)"
    case employer = "Employer (A–Z)"
    case grade = "Grade"
    case graduation = "Graduation year"
    case mostVisited = "Most visits"
    case leastVisited = "Fewest visits"
    case recentVisit = "Most recently visited"
    var id: String { rawValue }
}
enum StudentFilter: String, CaseIterable, Identifiable {
    case all = "All students"
    case notVisited = "Not visited"
    case visited = "Visited at least once"
    var id: String { rawValue }
}
struct StudentsView: View {
    @EnvironmentObject var store: VisitStore
    @State private var search = ""
    @State private var showingImport = false
    @State private var adding = false
    @State private var sort: StudentSort = .lastName
    @State private var filter: StudentFilter = .all

    var filtered: [Student] {
        let searched = store.db.students.filter { s in
            (search.isEmpty || s.fullName.localizedCaseInsensitiveContains(search) || s.employer.localizedCaseInsensitiveContains(search) || s.address.localizedCaseInsensitiveContains(search)) &&
            (filter == .all || (filter == .visited && s.hasVisited) || (filter == .notVisited && !s.hasVisited))
        }
        return searched.sorted { a, b in
            switch sort {
            case .lastName: return a.lastName.localizedStandardCompare(b.lastName) == .orderedAscending
            case .firstName: return a.firstName.localizedStandardCompare(b.firstName) == .orderedAscending
            case .employer: return a.employer.localizedStandardCompare(b.employer) == .orderedAscending
            case .grade: return (Int(a.grade) ?? 0) == (Int(b.grade) ?? 0) ? a.lastName < b.lastName : (Int(a.grade) ?? 0) > (Int(b.grade) ?? 0)
            case .graduation: return a.graduationYear == b.graduationYear ? a.lastName < b.lastName : a.graduationYear < b.graduationYear
            case .mostVisited: return a.visitCount == b.visitCount ? a.lastName < b.lastName : a.visitCount > b.visitCount
            case .leastVisited: return a.visitCount == b.visitCount ? a.lastName < b.lastName : a.visitCount < b.visitCount
            case .recentVisit: return a.lastVisit == b.lastVisit ? a.lastName < b.lastName : (a.lastVisit ?? .distantPast) > (b.lastVisit ?? .distantPast)
            }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing:8) {
                        Text("Sort: \(sort.rawValue)")
                        Spacer()
                        Text("\(filtered.count) students")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                ForEach(filtered) { s in
                    NavigationLink { StudentDetailView(studentID:s.id) } label: {
                        HStack(spacing:12) {
                            VStack(alignment:.leading,spacing:4) {
                                Text(s.fullName).font(.headline)
                                Text("\(s.employer) • Grade \(s.grade)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(s.visitCount)")
                                .font(.headline.monospacedDigit())
                                .padding(.horizontal,12).padding(.vertical,7)
                                .foregroundStyle(s.visitCount > 0 ? .indigo : .secondary)
                                .background(Color.indigo.opacity(s.visitCount > 0 ? 0.12 : 0.05),in:Capsule())
                                .accessibilityLabel("\(s.visitCount) recorded visits")
                        }
                    }
                }.onDelete { offsets in
                    let ids = offsets.map { filtered[$0].id }
                    store.db.students.removeAll { ids.contains($0.id) }
                }
            }
            .searchable(text:$search,prompt:"Student, employer or address")
            .navigationTitle("Students")
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("Import",systemImage:"square.and.arrow.down") { showingImport = true } }
                ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        Picker("Sort students", selection:$sort) {
                            ForEach(StudentSort.allCases) { choice in Text(choice.rawValue).tag(choice) }
                        }
                        Picker("Filter students", selection:$filter) {
                            ForEach(StudentFilter.allCases) { choice in Text(choice.rawValue).tag(choice) }
                        }
                    } label: { Label("Sort and filter",systemImage:"arrow.up.arrow.down.circle") }
                }
                ToolbarItem(placement:.topBarTrailing) { Button("Add",systemImage:"plus") { adding = true } }
            }
            .sheet(isPresented:$showingImport) { ImportView() }
            .sheet(isPresented:$adding) { StudentFormView(student:nil) }
        }
    }
}
struct StudentFormView: View {
    @EnvironmentObject var store: VisitStore
    @Environment(\.dismiss) var dismiss
    let student: Student?
    @State private var first = ""
    @State private var last = ""
    @State private var year = ""
    @State private var grade = ""
    @State private var employer = ""
    @State private var address = ""
    @State private var phone = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Student") { TextField("First name",text:$first); TextField("Last name",text:$last); TextField("Graduation year",text:$year).keyboardType(.numberPad); TextField("Grade",text:$grade) }
                Section("Workplace") { TextField("Employer name",text:$employer); TextField("Employer address",text:$address,axis:.vertical); TextField("Phone number",text:$phone).keyboardType(.phonePad) }
            }
            .navigationTitle(student == nil ? "Add student" : "Edit student")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") {dismiss()} }; ToolbarItem(placement:.confirmationAction) { Button("Save") { save() }.disabled(first.isEmpty || last.isEmpty) } }
            .onAppear { if let s = student { first=s.firstName;last=s.lastName;year=s.graduationYear;grade=s.grade;employer=s.employer;address=s.address;phone=s.phone } }
        }
    }
    func save() {
        var s = student ?? Student(firstName:first,lastName:last,graduationYear:year,grade:grade,employer:employer,address:address,phone:phone)
        s.firstName=first;s.lastName=last;s.graduationYear=year;s.grade=grade;s.employer=employer;s.address=address;s.phone=phone
        if student == nil { store.db.students.append(s) } else { store.update(s) }
        dismiss()
    }
}
struct StudentDetailView: View {
    @EnvironmentObject var store: VisitStore
    let studentID: UUID
    @State private var editing = false
    @State private var loggingVisit = false
    @State private var noteText = ""
    @State private var editNoteID: UUID?
    @State private var exportedFile: [URL] = []
    @State private var showingExport = false
    var student: Student? { store.student(studentID) }
    var body: some View {
        Group {
            if let s = student {
                List {
                    Section("Workplace") {
                        LabeledContent("Employer",value:s.employer)
                        LabeledContent("Address",value:s.address)
                        LabeledContent("Phone",value:s.phone)
                        LabeledContent("Grade",value:s.grade)
                        LabeledContent("Graduates",value:s.graduationYear)
                    }
                    Section("Visit history • \(s.visitCount) total") {
                        Button("Log a visit or contact",systemImage:"plus.circle") { loggingVisit = true }
                        Button("Export this student's visits", systemImage:"square.and.arrow.up") {
                            if let file = store.exportCSV(.visits,studentID:studentID) {
                                exportedFile = [file]; showingExport = true
                            }
                        }
                        if s.visitCount == 0 { Text("No visits recorded yet").foregroundStyle(.secondary) }
                        ForEach(s.allVisits.sorted { $0.at > $1.at }) { record in
                            HStack(alignment:.top,spacing:12) {
                                Image(systemName:record.kind.symbol).foregroundStyle(.indigo)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(record.kind.rawValue).font(.subheadline.bold())
                                    Text(record.at.formatted(date:.complete,time:.standard))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    if record.tripID != nil {
                                        Text("Recorded during a planned trip").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical,3)
                        }
                    }
                    Section("Notes") {
                        ForEach(s.notes.sorted { $0.updated > $1.updated }) { note in
                            Button { editNoteID=note.id;noteText=note.text } label: {
                                VStack(alignment:.leading,spacing:7) {
                                    Text(note.text).foregroundStyle(.primary)
                                    Text("Updated \(note.updated.formatted(date:.abbreviated,time:.shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.onDelete { offsets in
                            let sorted = s.notes.sorted { $0.updated > $1.updated }
                            let ids = offsets.map { sorted[$0].id }
                            var changed=s
                            changed.notes.removeAll { ids.contains($0.id) }
                            store.update(changed)
                        }
                        Button("Add note",systemImage:"square.and.pencil") { editNoteID=UUID();noteText="" }
                    }
                }
                .navigationTitle(s.fullName)
                .toolbar { Button("Edit") { editing=true } }
                .sheet(isPresented:$editing) { StudentFormView(student:s) }
                .sheet(isPresented:$loggingVisit) { ManualVisitView(studentID:studentID) }
                .sheet(isPresented:$showingExport) { ExportSheet(files:exportedFile) }
                .sheet(isPresented:Binding(get:{editNoteID != nil},set:{if !$0 {editNoteID=nil}})) {
                    NoteEditor(text:$noteText) {
                        var updated=s
                        if let i=updated.notes.firstIndex(where:{$0.id == editNoteID}) {
                            updated.notes[i].text=noteText;updated.notes[i].updated = .now
                        } else { updated.notes.append(StudentNote(text:noteText)) }
                        store.update(updated);editNoteID=nil
                    } onCancel: { editNoteID=nil }
                }
            } else { Text("Student not found") }
        }
    }
}
struct ManualVisitView: View {
    @EnvironmentObject var store: VisitStore
    @Environment(\.dismiss) private var dismiss
    let studentID: UUID
    @State private var kind: VisitKind = .inPerson
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section("Visit details") {
                    Picker("Type", selection:$kind) {
                        ForEach(VisitKind.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.menu)
                    DatePicker("Date and time",selection:$date,displayedComponents:[.date,.hourAndMinute])
                }
                Section {
                    Text("Manually logged contacts count toward this student's total. This does not add mileage or create a route.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Log visit")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Save") { store.recordVisit(studentID:studentID,kind:kind,at:date); dismiss() }
                }
            }
        }
    }
}
struct NoteEditor: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    var body: some View {
        NavigationStack {
            Form { TextEditor(text:$text).frame(minHeight:180) }
                .navigationTitle("Visit note")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel",action:onCancel) }; ToolbarItem(placement:.confirmationAction) {Button("Save",action:onSave).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)} }
        }
    }
}
struct ImportView: View {
    @EnvironmentObject var store: VisitStore
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var importedStudents: [Student] = []
    @State private var filename = ""
    @State private var filePicker = false
    @State private var replace = false
    @State private var loading = false
    var parsed: [Student] { filename.isEmpty ? CSVImport.parse(text) : importedStudents }
    var body: some View {
        NavigationStack {
            Form {
                Section("Select spreadsheet") {
                    Button("Choose CSV, TSV, or Excel .xlsx", systemImage:"doc.badge.plus") { filePicker = true }
                    if !filename.isEmpty { Label(filename, systemImage:"doc.text") }
                    Text("In Google Sheets: File → Download → Microsoft Excel (.xlsx) or Comma-separated values (.csv). Then select the saved file here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Or paste rows") {
                    Text("Paste a CSV with columns: First Name, Last Name, Graduation Year, Grade, Employer Name, Employer Address, Phone Number.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text:$text).frame(minHeight:100)
                        .onChange(of:text) { _, _ in filename = ""; importedStudents = [] }
                }
                Section("Preview • \(parsed.count) students") {
                    if parsed.isEmpty { Text("Select a file or paste a list to preview it.").foregroundStyle(.secondary) }
                    ForEach(parsed.prefix(15)) { student in
                        VStack(alignment:.leading,spacing:3) {
                            Text(student.fullName).font(.headline)
                            Text(student.employer + " • " + student.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if parsed.count > 15 { Text("And \(parsed.count - 15) more students…").foregroundStyle(.secondary) }
                }
                Section {
                    Toggle("Replace current students",isOn:$replace)
                    Text("Duplicates with the same student name and workplace address are skipped when adding.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import students")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") {dismiss()} }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Import \(parsed.count)") { applyImport() }.disabled(parsed.isEmpty || loading)
                }
            }
            .fileImporter(isPresented:$filePicker, allowedContentTypes:[.commaSeparatedText,.plainText,UTType(filenameExtension:"tsv") ?? .plainText,UTType(filenameExtension:"xlsx") ?? .data]) { result in
                do {
                    let url = try result.get()
                    let granted=url.startAccessingSecurityScopedResource()
                    defer { if granted {url.stopAccessingSecurityScopedResource()} }
                    let ext=url.pathExtension.lowercased()
                    let students: [Student]
                    if ext == "xlsx" { students = try SpreadsheetImport.students(from:url) }
                    else {
                        let bytes=try Data(contentsOf:url)
                        guard let string=String(data:bytes,encoding:.utf8) ?? String(data:bytes,encoding:.utf16) else {
                            throw NSError(domain:"WBL",code:1,userInfo:[NSLocalizedDescriptionKey:"Cannot decode file text"])
                        }
                        let clean=string.replacingOccurrences(of:"\u{FEFF}",with:"")
                        if ext == "tsv" || (clean.contains("\t") && !clean.contains(",")) {
                            students=CSVImport.students(fromRows: clean.components(separatedBy:.newlines).filter{ !$0.isEmpty }.map{$0.components(separatedBy:"\t")})
                        } else { students=CSVImport.parse(clean) }
                    }
                    filename=url.lastPathComponent
                    importedStudents=students
                    if students.isEmpty {store.errorMessage="No valid student rows found. Check the column headers and data."}
                } catch {store.errorMessage="Could not import spreadsheet: \(error.localizedDescription)"}
            }
        }
    }
    private func applyImport() {
        let incoming=parsed
        if replace { store.db.students=incoming; store.db.trips=[] }
        else {
            var existing=Set(store.db.students.map { ($0.fullName + "|" + $0.address).lowercased() })
            for student in incoming {
                let key=(student.fullName + "|" + student.address).lowercased()
                if existing.insert(key).inserted {store.db.students.append(student)}
            }
        }
        dismiss()
    }
}
