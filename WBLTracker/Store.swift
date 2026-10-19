import Foundation
import SwiftUI
import ZIPFoundation

@MainActor final class VisitStore: ObservableObject {
    @Published var db = Database() { didSet { save() } }
    @Published var errorMessage: String?
    private let filename = "wbl-visits.json"
    init() { load() }
    private var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename) }
    private func load() {
        do { db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url)) }
        catch { if FileManager.default.fileExists(atPath: url.path) { errorMessage = "Could not open saved data: \(error.localizedDescription)" } }
    }
    private func save() {
        do { let data = try JSONEncoder().encode(db); try data.write(to: url, options: .atomic) }
        catch { errorMessage = "Could not save data: \(error.localizedDescription)" }
    }
    func update(_ student: Student) { if let i = db.students.firstIndex(where: { $0.id == student.id }) { db.students[i] = student } }
    func student(_ id: UUID) -> Student? { db.students.first { $0.id == id } }
    func visit(tripID: UUID, stopID: UUID) {
        guard let t = db.trips.firstIndex(where: { $0.id == tripID }), let s = db.trips[t].stops.firstIndex(where: { $0.id == stopID }), db.trips[t].stops[s].arrival == nil else { return }
        let now = Date(); let studentID = db.trips[t].stops[s].studentID
        db.trips[t].stops[s].arrival = now
        if let i = db.students.firstIndex(where: { $0.id == studentID }) { db.students[i].visits.append(now) }
    }
    func updateTrip(_ trip: Trip) { if let i = db.trips.firstIndex(where: { $0.id == trip.id }) { db.trips[i] = trip } }
    var activeTrip: Trip? { db.trips.first { $0.isActive } }
    func startNewMonth() {
        // Maintain identities, workplace details and notes; archive old data in a separate export first.
        for i in db.students.indices { db.students[i].visits = [] }
        db.trips = []
    }
    func fullReset() { db = Database() }
    func exportFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WBL-Export-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let csvs: [(String, String)] = [
                ("students.csv", studentsCSV), ("visits.csv", visitsCSV),
                ("notes.csv", notesCSV), ("trips.csv", tripsCSV), ("trip_stops.csv", stopsCSV)
            ]
            for (name, contents) in csvs {
                try ("\u{FEFF}" + contents).write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .iso8601]
            try encoder.encode(db).write(to: folder.appendingPathComponent("full_backup.json"), options: .atomic)
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("WBL-Complete-Export-" + UUID().uuidString + ".zip")
            guard let archive = Archive(url: zipURL, accessMode: .create) else { throw NSError(domain:"WBL",code:2,userInfo:[NSLocalizedDescriptionKey:"Could not create ZIP export."]) }
            for name in csvs.map({$0.0}) + ["full_backup.json"] {
                try archive.addEntry(with: name, relativeTo: folder)
            }
            return [zipURL]
        } catch { errorMessage = "Export failed: \(error.localizedDescription)"; return [] }
    }
    private func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private func line(_ fields: [String]) -> String { fields.map(q).joined(separator: ",") }
    private func csv(_ header: [String], _ rows: [[String]]) -> String { ([line(header)] + rows.map(line)).joined(separator: "\r\n") }
    private func timestamp(_ date: Date?) -> String { date.map { ISO8601DateFormatter().string(from: $0) } ?? "" }
    var studentsCSV: String { csv(["Student ID", "First Name", "Last Name", "Graduation Year", "Grade", "Employer Name", "Employer Address", "Phone Number", "Visited", "Visit Count", "Last Visit"], db.students.map { s in
        [s.id.uuidString, s.firstName, s.lastName, s.graduationYear, s.grade, s.employer, s.address, s.phone, s.hasVisited ? "Yes":"No", "\(s.visits.count)", timestamp(s.visits.max())]
    }) }
    var visitsCSV: String { csv(["Student ID", "Student", "Employer Address", "Visited At"], db.students.flatMap { s in s.visits.map { [s.id.uuidString,s.fullName,s.address,timestamp($0)] } }) }
    var notesCSV: String { csv(["Student ID", "Student", "Note ID", "Text", "Created", "Updated"], db.students.flatMap { s in s.notes.map { [s.id.uuidString,s.fullName,$0.id.uuidString,$0.text,timestamp($0.created),timestamp($0.updated)] } }) }
    var tripsCSV: String { csv(["Trip ID", "Visit Date", "Created", "Start Address", "Round Trip", "Estimated Miles", "Final Miles", "Completed"], db.trips.map { t in
        [t.id.uuidString,timestamp(t.date),timestamp(t.created),t.startAddress,t.roundTrip ? "Yes":"No", t.estimatedMiles.map { String($0) } ?? "",t.finalMiles.map { String($0) } ?? "", timestamp(t.completed)]
    }) }
    var stopsCSV: String { csv(["Trip ID", "Stop ID", "Stop Order", "Student ID", "Student", "Employer", "Address", "Visited At"], db.trips.flatMap { t in t.stops.enumerated().map { idx, stop in
        let s = student(stop.studentID)
        return [t.id.uuidString,stop.id.uuidString,"\(idx + 1)",stop.studentID.uuidString,s?.fullName ?? "(Deleted student)",s?.employer ?? "",s?.address ?? "",timestamp(stop.arrival)]
    } }) }
    var csvExport: String {
        let header = "First Name,Last Name,Graduation Year,Grade,Employer Name,Employer Address,Phone Number,Visited"
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        return ([header] + db.students.map { s in
            [s.firstName,s.lastName,s.graduationYear,s.grade,s.employer,s.address,s.phone,s.hasVisited ? "Yes" : "No"].map(quote).joined(separator: ",")
        }).joined(separator: "\n")
    }
}

// RFC-4180-like CSV parser: handles quoted fields, escaped quotes, commas, and line breaks.
enum CSVImport {
    static func rows(_ text: String) -> [[String]] {
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i+1 < chars.count && chars[i+1] == "\n" { i += 1 }
                row.append(field); if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { result.append(row) }; row = []; field = ""
            } else { field.append(c) }
            i += 1
        }
        row.append(field); if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { result.append(row) }
        return result
    }
    static func parse(_ text: String) -> [Student] { students(fromRows: rows(text)) }
    static func students(fromRows data: [[String]]) -> [Student] {
        guard !data.isEmpty else { return [] }
        let normalize: (String) -> String = { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        let header = data[0].map(normalize)
        let aliases = [ ["firstname","first"], ["lastname","last"], ["graduationyear","gradyear","graduation"], ["grade","gradelevel"], ["employername","employer","company"], ["employeraddress","address","workplaceaddress"], ["phonenumber","phone","telephone"] ]
        let indexes = aliases.map { a in header.firstIndex(where: { a.contains($0) }) }
        let hasHeader = indexes.compactMap { $0 }.count >= 3
        return (hasHeader ? Array(data.dropFirst()) : data).compactMap { r in
            func field(_ column: Int) -> String { let index = hasHeader ? (indexes[column] ?? column) : column; return index < r.count ? r[index].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            guard !field(0).isEmpty, !field(1).isEmpty else { return nil }
            return Student(firstName: field(0), lastName: field(1), graduationYear: field(2), grade: field(3), employer: field(4), address: field(5), phone: field(6))
        }
    }
}
