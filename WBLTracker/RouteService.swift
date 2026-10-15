import Foundation
import CoreLocation
import MapKit

@MainActor final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationDenied = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() { manager.requestWhenInUseAuthorization(); manager.requestLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { print("Location unavailable: \(error.localizedDescription)") }
}

struct RouteResult {
    let orderedIDs: [UUID]
    let estimatedMiles: Double
    let originName: String
}
enum RouteError: LocalizedError {
    case missingAddress(String), noLocation, routeUnavailable
    var errorDescription: String? {
        switch self {
        case .missingAddress(let name): return "Missing or unrecognized workplace address: \(name)"
        case .noLocation: return "Allow location access or enter a starting address."
        case .routeUnavailable: return "Could not calculate driving directions. Check addresses and network connection."
        }
    }
}
@MainActor enum RouteService {
    static func geocode(_ address: String) async throws -> CLLocationCoordinate2D {
        let marks = try await CLGeocoder().geocodeAddressString(address)
        guard let point = marks.first?.location?.coordinate else { throw RouteError.missingAddress(address) }
        return point
    }
    static func miles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude:a.latitude,longitude:a.longitude).distance(from: CLLocation(latitude:b.latitude,longitude:b.longitude)) / 1609.344
    }
    static func roadMiles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) async throws -> Double {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate:a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate:b))
        request.transportType = .automobile
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw RouteError.routeUnavailable }
        return route.distance / 1609.344
    }
    // Nearest-neighbor ordering by geographic distance, then driving miles on the chosen legs.
    // This is a heuristic, not an exact traffic-aware traveling-salesperson solution.
    static func plan(start: CLLocationCoordinate2D, originName: String, students: [Student], roundTrip: Bool) async throws -> RouteResult {
        var locations: [(UUID, CLLocationCoordinate2D)] = []
        for student in students {
            guard !student.address.isEmpty else { throw RouteError.missingAddress(student.fullName) }
            locations.append((student.id, try await geocode(student.address)))
        }
        var ordered: [(UUID, CLLocationCoordinate2D)] = []; var cursor = start
        while !locations.isEmpty {
            let index = locations.indices.min(by: { miles(cursor, locations[$0].1) < miles(cursor, locations[$1].1) })!
            let next = locations.remove(at: index); ordered.append(next); cursor = next.1
        }
        // 2-opt reversal improves the geographic tour, including the optional return leg.
        if ordered.count >= 3 {
            var improved = true
            func pathCost(_ v: [(UUID, CLLocationCoordinate2D)]) -> Double {
                var cost = miles(start, v[0].1)
                for k in 1..<v.count { cost += miles(v[k-1].1,v[k].1) }
                if roundTrip { cost += miles(v.last!.1,start) }
                return cost
            }
            var turns = 0
            while improved && turns < 8 {
                turns += 1; improved = false
                for i in 0..<(ordered.count-1) {
                    for j in (i+1)..<ordered.count {
                        var candidate = ordered
                        candidate.replaceSubrange(i...j, with: Array(candidate[i...j].reversed()))
                        if pathCost(candidate) + 0.0001 < pathCost(ordered) { ordered = candidate; improved = true }
                    }
                }
            }
        }
        var total = 0.0; cursor = start
        for stop in ordered { total += try await roadMiles(cursor,stop.1); cursor = stop.1 }
        if roundTrip { total += try await roadMiles(cursor,start) }
        return RouteResult(orderedIDs:ordered.map { $0.0 },estimatedMiles:total,originName:originName)
    }
    static func googleURL(origin: String, addresses: [String], roundTrip: Bool) -> URL? {
        guard let last = addresses.last else { return nil }
        let destination = roundTrip ? origin : last
        let intermediates = roundTrip ? addresses : Array(addresses.dropLast())
        var c = URLComponents(string:"https://www.google.com/maps/dir/")!
        c.queryItems = [URLQueryItem(name:"api",value:"1"),URLQueryItem(name:"origin",value:origin),URLQueryItem(name:"destination",value:destination),URLQueryItem(name:"travelmode",value:"driving")]
        if !intermediates.isEmpty { c.queryItems!.append(URLQueryItem(name:"waypoints",value:intermediates.joined(separator:"|"))) }
        return c.url
    }
    static func appleURL(start: String, destination: String) -> URL? {
        var c = URLComponents(string:"https://maps.apple.com/")!
        c.queryItems = [URLQueryItem(name:"saddr",value:start),URLQueryItem(name:"daddr",value:destination),URLQueryItem(name:"dirflg",value:"d")]
        return c.url
    }
}
