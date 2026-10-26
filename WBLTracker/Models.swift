import Foundation

enum VisitKind: String, CaseIterable, Codable, Identifiable {
    case inPerson = "In person"
    case zoom = "Zoom"
    case phoneCall = "Phone call"
    case message = "Message"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .inPerson: return "person.crop.circle"
        case .zoom: return "video"
        case .phoneCall: return "phone"
        case .message: return "message"
        }
    }
}

struct VisitRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var at: Date
    var kind: VisitKind
    var tripID: UUID? = nil
    var stopID: UUID? = nil
}

struct Student: Identifiable, Codable, Hashable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var graduationYear: String
    var grade: String
    var employer: String
    var address: String
    var phone: String
    // Legacy format retained for decoding installations from before visit types.
    var visits: [Date] = []
    // Optional permits decoding old JSON that did not contain this key.
    var visitRecords: [VisitRecord]? = nil
    var notes: [StudentNote] = []
    var fullName: String { "\(firstName) \(lastName)" }
    var allVisits: [VisitRecord] {
        visitRecords ?? visits.map { VisitRecord(at: $0, kind: .inPerson) }
    }
    var visitCount: Int { allVisits.count }
    var lastVisit: Date? { allVisits.map(\.at).max() }
    var hasVisited: Bool { visitCount > 0 }
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
    // nil in old saved trips, which were all in-person.
    var kind: VisitKind? = nil
    var visitKind: VisitKind { kind ?? .inPerson }
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
    var inPersonStops: [TripStop] { stops.filter { $0.visitKind == .inPerson } }
}

struct Database: Codable {
    var students: [Student] = []
    var trips: [Trip] = []
}
