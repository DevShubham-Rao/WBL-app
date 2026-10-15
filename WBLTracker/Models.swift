import Foundation

struct Student: Identifiable, Codable, Hashable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var graduationYear: String
    var grade: String
    var employer: String
    var address: String
    var phone: String
    var visits: [Date] = []
    var notes: [StudentNote] = []
    var fullName: String { "\(firstName) \(lastName)" }
    var hasVisited: Bool { !visits.isEmpty }
}
struct StudentNote: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var created: Date = .now
    var updated: Date = .now
}
struct TripStop: Identifiable, Codable, Hashable {
    var id = UUID()
    var studentID: UUID
    var arrival: Date? = nil
}
struct Trip: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var created: Date = .now
    var startAddress: String
    var stops: [TripStop]
    var roundTrip: Bool
    var estimatedMiles: Double? = nil
    var finalMiles: Double? = nil
    var completed: Date? = nil
    var isActive: Bool { completed == nil }
}
struct Database: Codable { var students: [Student] = []; var trips: [Trip] = [] }
