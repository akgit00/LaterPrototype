import Foundation
import CoreLocation

/// Wraps CoreLocation so views can request permission, read the user's current
/// coordinate, and reverse-geocode pins into readable addresses.
@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    /// The most recent fix, when permission has been granted.
    private(set) var currentCoordinate: CLLocationCoordinate2D?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Prompts for permission if needed, then starts location updates.
    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    /// Reverse-geocodes a coordinate into a short, human-readable address.
    nonisolated static func address(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        let parts: [String?] = [
            placemark.name,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country,
        ]
        var seen = Set<String>()
        let unique = parts.compactMap { $0 }.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.currentCoordinate = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: the user can still search or tap the map to place pins.
    }
}
