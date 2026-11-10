import Foundation
import CoreLocation
import Combine

/// Localização atual do usuário, com endereço aproximado para o modelo
/// conseguir responder "qual mercado/escola é o mais perto".
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var summary: String?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocoded: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let coordinate = String(
            format: "%.4f, %.4f",
            location.coordinate.latitude,
            location.coordinate.longitude
        )

        if let previous = lastGeocoded,
           previous.distance(from: location) < 400,
           let existing = summary {
            summary = existing
            return
        }

        lastGeocoded = location
        summary = coordinate

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self, let place = placemarks?.first else { return }
            let parts = [
                place.thoroughfare,
                place.subLocality,
                place.locality,
                place.administrativeArea
            ].compactMap { $0 }.filter { !$0.isEmpty }

            let address = parts.joined(separator: ", ")
            let text = address.isEmpty ? coordinate : "\(address) (\(coordinate))"
            DispatchQueue.main.async {
                self.summary = text
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silencioso: sem localização o app continua funcionando normalmente.
    }
}
