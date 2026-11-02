import Foundation

/// Retention for student records. A student graduating in 2028 is due for removal
/// on July 1, 2029 (the summer after one additional academic year).
/// Schools may have different legal record-retention obligations: confirm this
/// cutoff with an authorized district records administrator before using real data.
enum RetentionPolicy {
    struct CleanupResult {
        let database: Database
        let removedStudents: Int
        let removedTrips: Int
    }

    static func deletionDate(for graduationYear: String, calendar: Calendar = .current) -> Date? {
        let value = graduationYear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let year = Int(value), (1900...2100).contains(year) else { return nil }
        return calendar.date(from: DateComponents(year: year + 1, month: 7, day: 1))
    }

    static func isExpired(_ student: Student, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let cutoff = deletionDate(for: student.graduationYear, calendar: calendar) else { return false }
        return now >= cutoff
    }

    static func cleanup(_ original: Database, now: Date = .now, calendar: Calendar = .current) -> CleanupResult {
        let expiredIDs = Set(original.students.filter { isExpired($0, now: now, calendar: calendar) }.map(\.id))
        guard !expiredIDs.isEmpty else {
            return CleanupResult(database: original, removedStudents: 0, removedTrips: 0)
        }

        var cleaned = original
        cleaned.students.removeAll { expiredIDs.contains($0.id) }

        // Even an aggregate trip can expose the addresses visited and whom the
        // teacher met. Remove a full trip if it includes an expired student.
        // Other students' independent visit timestamps are preserved.
        let tripsToRemove = Set(original.trips.filter { trip in
            trip.stops.contains { expiredIDs.contains($0.studentID) }
        }.map(\.id))
        cleaned.trips.removeAll { tripsToRemove.contains($0.id) }

        // Remove pointers to deleted trip/stop records from the retained students.
        for index in cleaned.students.indices {
            guard var visits = cleaned.students[index].visitRecords else { continue }
            for recordIndex in visits.indices where visits[recordIndex].tripID.map(tripsToRemove.contains) == true {
                visits[recordIndex].tripID = nil
                visits[recordIndex].stopID = nil
            }
            cleaned.students[index].visitRecords = visits
        }

        return CleanupResult(database: cleaned,
                             removedStudents: expiredIDs.count,
                             removedTrips: tripsToRemove.count)
    }
}
