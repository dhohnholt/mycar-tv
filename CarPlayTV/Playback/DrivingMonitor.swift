import CoreLocation

/// Watches GPS speed while CarPlay is connected so car-screen video can pause when the vehicle moves.
@MainActor
final class DrivingMonitor: NSObject, ObservableObject {
    static let shared = DrivingMonitor()

    /// Above ~5 mph counts as moving; below ~1 mph counts as stopped (hysteresis avoids flicker).
    private static let movingSpeed: CLLocationSpeed = 2.2
    private static let stoppedSpeed: CLLocationSpeed = 0.5

    @Published private(set) var isMoving = false
    @Published private(set) var isAuthorized = true

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func setActive(_ active: Bool) {
        if active {
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            isMoving = false
        }
    }
}

extension DrivingMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let speed = locations.last?.speed, speed >= 0 else { return }
        MainActor.assumeIsolated {
            if speed > Self.movingSpeed, !isMoving {
                isMoving = true
            } else if speed < Self.stoppedSpeed, isMoving {
                isMoving = false
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            isAuthorized = status != .denied && status != .restricted
        }
    }
}
