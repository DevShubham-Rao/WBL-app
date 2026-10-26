import Foundation
import SwiftUI
import ZIPFoundation

enum ReportKind: String, CaseIterable, Identifiable {
    case mileage = "Mileage"
    case visits = "Visits"
    case students = "Students"
    var id: String { rawValue }
    var filename: String { rawValue.lowercased() + ".csv" }
}

@MainActor final class VisitStore: ObservableObject {
    @Published var db = Database() { didSet { save() } }
    @Published var errorMessage: String?
    private let filename = "wbl-visits.json"

    init() { load() }
    private var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }
    private func load() {
        do {
            var loaded = try JSONDecoder().decode(Database.self, from: Data(contentsOf: url))
            // Convert old date-only visit arrays once. Keep all old trip records and timestamps.
            // Old visits are classified In person because the original app had no visit-type field.
            for i in loaded.students.indices {
                if loaded.students[i].visitRecords == nil {
                    loaded.students[i].visitRecords = loaded.students[i].visits.map {
                        VisitRecord(at: $0, kind: .inPerson)
                    }
                } else if !loaded.students[i].visits.isEmpty {
                    loaded.students[i].visitRecords!.append(contentsOf: loaded.students[i].visits.map {
                        VisitRecord(at: $0, kind: .inPerson)
                    })
                }
                loaded.students[i].visits = []
            }
            db = loaded
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                errorMessage = "Could not open saved data: \(error.localizedDescription)"
            }
        }
    }
    private func save() {
        do {
            let data = try JSONEncoder().encode(db)
            try data.write(to: url, options: .atomic)
        } catch { errorMessage = "Could not save data: \(error.localizedDescription)" }
    }

    func update(_ student: Student) {
        if let index = db.students.firstIndex(where: { $0.id == student.id }) { db.students[index] = student }
    }
    func student(_ id: UUID) -> Student? { db.students.first { $0.id == id } }

    func visit(tripID: UUID, stopID: UUID) {
        guard let t = db.trips.firstIndex(where: { $0.id == tripID }),
              let si = db.trips[t].stops.firstIndex(where: { $0.id == stopID }),
              db.trips[t].stops[si].arrival == nil else { return }
        let now = Date()
        let stop = db.trips[t].stops[si]
        db.trips[t].stops[si].arrival = now
        recordVisit(studentID: stop.studentID, kind: stop.visitKind, at: now, tripID: tripID, stopID: stopID)
    }
    func recordVisit(studentID: UUID, kind: VisitKind, at: Date = .now, tripID: UUID? = nil, stopID: UUID? = nil) {
        guard let i = db.students.firstIndex(where: { $0.id == studentID }) else { return }
        if db.students[i].visitRecords == nil { db.students[i].visitRecords = db.students[i].allVisits }
        db.students[i].visitRecords!.append(VisitRecord(at: at, kind: kind, tripID: tripID, stopID: stopID))
    }
    func updateTrip(_ trip: Trip) {
        if let i = db.trips.firstIndex(where: { $0.id == trip.id }) { db.trips[i] = trip }
    }
    var activeTrip: Trip? { db.trips.first { $0.isActive } }

    // No monthly reset: visits, mileage and notes persist until the explicit full reset.
    func fullReset() { db = Database() }

    private func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private func line(_ fields: [String]) -> String { fields.map(q).joined(separator: ",") }
    private func csv(_ header: [String], _ rows: [[String]]) -> String {
        ([line(header)] + rows.map(line)).joined(separator: "\r\n")
    }
    private func timestamp(_ date: Date?) -> String {
        date.map { ISO8601DateFormatter().string(from: $0) } ?? ""
    }
    private func inRange(_ date: Date, start: Date?, end: Date?) -> Bool {
        let calendar = Calendar.current
        if let start = start, date < calendar.startOfDay(for: start) { return false }
        if let end = end,
           let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)),
           date >= exclusiveEnd { return false }
        return true
    }

    func csvReport(_ kind: ReportKind, start: Date? = nil, end: Date? = nil, studentID: UUID? = nil) -> String {
        switch kind {
        case .students:
            return csv(["Student ID", "First Name", "Last Name", "Graduation Year", "Grade", "Employer", "Employer Address", "Phone", "Visit Count", "Last Visit"], db.students.filter { s in studentID.map { s.id == $0 } ?? true }.map { s in
                [s.id.uuidString, s.firstName, s.lastName, s.graduationYear, s.grade, s.employer, s.address, s.phone, "\(s.visitCount)", timestamp(s.lastVisit)]
            })
        case .visits:
            let rows: [[String]] = db.students.filter { s in studentID.map { s.id == $0 } ?? true }.flatMap { s in
                s.allVisits.filter { inRange($0.at, start:start, end:end) }.sorted { $0.at > $1.at }.map { visit in
                    [s.id.uuidString, s.fullName, s.employer, s.address, visit.kind.rawValue, timestamp(visit.at), visit.tripID?.uuidString ?? "", visit.id.uuidString]
                }
            }.sorted { $0[5] > $1[5] }
            return csv(["Student ID", "Student", "Employer", "Employer Address", "Visit Type", "Visited At", "Trip ID", "Visit ID"], rows)
        case .mileage:
            let trips = db.trips.filter { $0.completed != nil && $0.inPersonStops.count > 0 && inRange($0.date,start:start,end:end) }.sorted { $0.date > $1.date }
            return csv(["Trip ID", "Trip Date", "Start Address", "In-Person Stops", "Round Trip", "Estimated Miles", "Saved Miles", "Completed"], trips.map { trip in
                [trip.id.uuidString, timestamp(trip.date), trip.startAddress, trip.inPersonStops.compactMap { student($0.studentID)?.fullName }.joined(separator:"; "), trip.roundTrip ? "Yes" : "No", trip.estimatedMiles.map { String(format: "%.2f", $0) } ?? "", trip.finalMiles.map { String(format: "%.2f", $0) } ?? "", timestamp(trip.completed)]
            })
        }
    }

    func exportCSV(_ kind: ReportKind, start: Date? = nil, end: Date? = nil, studentID: UUID? = nil) -> URL? {
        if let start = start, let end = end, Calendar.current.startOfDay(for:start) > Calendar.current.startOfDay(for:end) {
            errorMessage = "The start date must be on or before the end date."
            return nil
        }
        let name = "WBL-\(kind.rawValue)-\(UUID().uuidString).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try ("\u{FEFF}" + csvReport(kind,start:start,end:end,studentID:studentID)).write(to:path,atomically:true,encoding:.utf8)
            return path
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    var studentsCSV: String { csvReport(.students) }
    var visitsCSV: String { csvReport(.visits) }
    var tripsCSV: String {
        csv(["Trip ID", "Visit Date", "Created", "Start Address", "Round Trip", "In-Person Stops", "Estimated Miles", "Final Miles", "Completed"], db.trips.map { t in
            [t.id.uuidString,timestamp(t.date),timestamp(t.created),t.startAddress,t.roundTrip ? "Yes":"No", "\(t.inPersonStops.count)", t.estimatedMiles.map { String($0) } ?? "",t.finalMiles.map { String($0) } ?? "", timestamp(t.completed)]
        })
    }
    var notesCSV: String {
        csv(["Student ID", "Student", "Note ID", "Text", "Created", "Updated"], db.students.flatMap { s in s.notes.map { n in
            [s.id.uuidString,s.fullName,n.id.uuidString,n.text,timestamp(n.created),timestamp(n.updated)]
        } })
    }
    var stopsCSV: String {
        csv(["Trip ID", "Stop ID", "Stop Order", "Student ID", "Student", "Employer", "Address", "Visit Type", "Visited At"], db.trips.flatMap { t in t.stops.enumerated().map { idx, stop in
            let s = student(stop.studentID)
            return [t.id.uuidString,stop.id.uuidString,"\(idx + 1)",stop.studentID.uuidString,s?.fullName ?? "(Deleted student)",s?.employer ?? "",s?.address ?? "",stop.visitKind.rawValue,timestamp(stop.arrival)]
        } })
    }
    // For backward compatibility with any remaining original screens.
    var csvExport: String { studentsCSV }

    func exportFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WBL-Export-" + UUID().uuidString, isDirectory:true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories:true)
            let csvs: [(String,String)] = [
                ("students.csv", studentsCSV), ("visits.csv", visitsCSV), ("mileage.csv", csvReport(.mileage)),
                ("notes.csv", notesCSV), ("trips.csv", tripsCSV), ("trip_stops.csv", stopsCSV)
            ]
            for (name, contents) in csvs {
                try ("\u{FEFF}" + contents).write(to: folder.appendingPathComponent(name), atomically:true, encoding:.utf8)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(db).write(to:folder.appendingPathComponent("full_backup.json"),options:.atomic)
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("WBL-Complete-Export-" + UUID().uuidString + ".zip")
            guard let archive = Archive(url: zipURL, accessMode: .create) else {
                throw NSError(domain:"WBL",code:2,userInfo:[NSLocalizedDescriptionKey:"Could not create ZIP export."])
            }
            for name in csvs.map({$0.0}) + ["full_backup.json"] { try archive.addEntry(with:name,relativeTo:folder) }
            return [zipURL]
        } catch { errorMessage = "Export failed: \(error.localizedDescription)"; return [] }
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
