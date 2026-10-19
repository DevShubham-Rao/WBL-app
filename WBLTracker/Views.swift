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
                        summary("Visited", "\(store.db.students.filter(\.hasVisited).count)","checkmark.circle")
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
struct StudentsView: View {
    @EnvironmentObject var store: VisitStore
    @State private var search = ""
    @State private var showingImport = false
    @State private var adding = false
    var filtered: [Student] { store.db.students.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) || $0.employer.localizedCaseInsensitiveContains(search) } .sorted { $0.lastName.localizedStandardCompare($1.lastName) == .orderedAscending } }
    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { s in
                    NavigationLink { StudentDetailView(studentID:s.id) } label: {
                        HStack {
                            VStack(alignment:.leading,spacing:4) { Text(s.fullName).font(.headline); Text("\(s.employer) • Grade \(s.grade)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName:s.hasVisited ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(s.hasVisited ? .green : .orange)
                                .accessibilityLabel(s.hasVisited ? "Visited" : "Not visited")
                        }
                    }
                }.onDelete { offsets in
                    let ids = offsets.map { filtered[$0].id }
                    store.db.students.removeAll { ids.contains($0.id) }
                }
            }
            .searchable(text:$search,prompt:"Student or employer")
            .navigationTitle("Students")
            .toolbar {
                ToolbarItem(placement:.topBarLeading) { Button("Import",systemImage:"square.and.arrow.down") { showingImport = true } }
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
    @State private var noteText = ""
    @State private var editNoteID: UUID?
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
                    Section("Visits • \(s.visits.count)") {
                        if s.visits.isEmpty { Text("Not visited yet").foregroundStyle(.secondary) }
                        ForEach(s.visits.sorted(by:>),id:\.self) { date in Text(date.formatted(date:.abbreviated,time:.shortened)) }
                    }
                    Section("Notes") {
                        ForEach(s.notes.sorted { $0.updated > $1.updated }) { note in
                            Button { editNoteID=note.id;noteText=note.text } label: {
                                VStack(alignment:.leading,spacing:7) { Text(note.text).foregroundStyle(.primary); Text("Updated \(note.updated.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.onDelete { offsets in
                            let sorted = s.notes.sorted { $0.updated > $1.updated }; let ids = offsets.map { sorted[$0].id }
                            var changed=s;changed.notes.removeAll { ids.contains($0.id) };store.update(changed)
                        }
                        Button("Add note",systemImage:"square.and.pencil") { editNoteID=UUID();noteText="" }
                    }
                }
                .navigationTitle(s.fullName)
                .toolbar { Button("Edit") { editing=true } }
                .sheet(isPresented:$editing) { StudentFormView(student:s) }
                .sheet(isPresented:Binding(get:{editNoteID != nil},set:{if !$0 {editNoteID=nil}})) { NoteEditor(text:$noteText) {
                    var updated=s
                    if let i=updated.notes.firstIndex(where:{$0.id == editNoteID}) { updated.notes[i].text=noteText;updated.notes[i].updated = .now }
                    else { updated.notes.append(StudentNote(text:noteText)) }
                    store.update(updated);editNoteID=nil
                } onCancel: { editNoteID=nil } }
            } else { Text("Student not found") }
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
