import Foundation
import RadrootsKit

public struct FieldLocationCheckInReading: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracyMeters: Double
    public let capturedAt: Date

    init(reading: RadrootsLocationReading) {
        self.latitude = reading.coordinate.latitude
        self.longitude = reading.coordinate.longitude
        self.horizontalAccuracyMeters = reading.horizontalAccuracyMeters
        self.capturedAt = reading.capturedAt
    }

    public var coordinateSummary: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    public var accuracySummary: String {
        String(format: "within %.0f m", horizontalAccuracyMeters)
    }
}

public enum FieldLocationCheckInState: Equatable, Sendable {
    case idle(RadrootsLocationServicesAvailability)
    case checking(RadrootsLocationServicesAvailability)
    case checkedIn(FieldLocationCheckInReading)
    case failed(RadrootsLocationServicesAvailability?, String)

    public var availability: RadrootsLocationServicesAvailability? {
        switch self {
        case .idle(let availability):
            availability
        case .checking(let availability):
            availability
        case .checkedIn:
            nil
        case .failed(let availability, _):
            availability
        }
    }
}

public struct FieldLocationCheckIn: Sendable {
    private let locationServices: any RadrootsLocationServices
    private let request: RadrootsCurrentLocationRequest

    public init(
        locationServices: any RadrootsLocationServices = RadrootsAppleLocationServices(),
        request: RadrootsCurrentLocationRequest? = nil
    ) {
        self.locationServices = locationServices
        self.request = request ?? Self.defaultRequest()
    }

    static func configured() -> Self {
        guard let mode = FieldLocationCheckInUITestMode.current else {
            return Self()
        }
        return Self(locationServices: FieldLocationCheckInUITestLocationServices(mode: mode))
    }

    public func status() async -> FieldLocationCheckInState {
        .idle(await locationServices.currentAvailability())
    }

    public func checkIn() async -> FieldLocationCheckInState {
        let availability = await locationServices.currentAvailability()
        guard availability.locationServicesEnabled else {
            return .failed(availability, "Location Services are disabled.")
        }
        do {
            if availability.authorization == .notDetermined {
                let authorization = try await locationServices.requestWhenInUseAuthorization()
                guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
                    return .failed(
                        RadrootsLocationServicesAvailability(
                            locationServicesEnabled: true,
                            authorization: authorization
                        ),
                        "Location permission was not granted."
                    )
                }
            }
            let result = try await locationServices.currentLocation(request)
            return .checkedIn(FieldLocationCheckInReading(reading: result.reading))
        } catch RadrootsLocationServicesError.permissionDenied(let message) {
            return .failed(availability, message)
        } catch RadrootsLocationServicesError.unavailable(let message) {
            return .failed(availability, message)
        } catch RadrootsLocationServicesError.timeout(let message) {
            return .failed(availability, message)
        } catch RadrootsLocationServicesError.cancelled(let message) {
            return .failed(availability, message)
        } catch {
            return .failed(availability, error.localizedDescription)
        }
    }

    private static func defaultRequest() -> RadrootsCurrentLocationRequest {
        do {
            return try RadrootsCurrentLocationRequest(
                timeoutSeconds: 10,
                desiredAccuracyMeters: 100,
                maximumCachedReadingAgeSeconds: 30
            )
        } catch {
            preconditionFailure("invalid default location check-in request")
        }
    }
}

private enum FieldLocationCheckInUITestMode: String {
    case success
    case denied
    case unavailable
    case timeout

    static var current: Self? {
        guard ProcessInfo.processInfo.environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" else {
            return nil
        }
        guard let raw = ProcessInfo.processInfo.environment["RADROOTS_FIELD_IOS_UI_TEST_LOCATION_MODE"] else {
            return nil
        }
        return Self(rawValue: raw)
    }
}

private actor FieldLocationCheckInUITestLocationServices: RadrootsLocationServices {
    private let mode: FieldLocationCheckInUITestMode

    init(mode: FieldLocationCheckInUITestMode) {
        self.mode = mode
    }

    func currentAvailability() async -> RadrootsLocationServicesAvailability {
        switch mode {
        case .success:
            RadrootsLocationServicesAvailability(locationServicesEnabled: true, authorization: .authorizedWhenInUse)
        case .denied:
            RadrootsLocationServicesAvailability(locationServicesEnabled: true, authorization: .denied)
        case .unavailable:
            RadrootsLocationServicesAvailability(locationServicesEnabled: false, authorization: .unavailable)
        case .timeout:
            RadrootsLocationServicesAvailability(locationServicesEnabled: true, authorization: .authorizedWhenInUse)
        }
    }

    func requestWhenInUseAuthorization() async throws -> RadrootsLocationAuthorization {
        switch mode {
        case .success, .timeout:
            .authorizedWhenInUse
        case .denied:
            throw RadrootsLocationServicesError.permissionDenied("location permission is denied")
        case .unavailable:
            throw RadrootsLocationServicesError.unavailable("location services are unavailable")
        }
    }

    func currentLocation(_ request: RadrootsCurrentLocationRequest) async throws -> RadrootsCurrentLocationResult {
        switch mode {
        case .success:
            let reading = try RadrootsLocationReading(
                coordinate: RadrootsLocationCoordinate(latitude: 49.2827, longitude: -123.1207),
                horizontalAccuracyMeters: 12,
                capturedAt: Date()
            )
            return try RadrootsCurrentLocationResult(reading: reading, authorization: .authorizedWhenInUse)
        case .denied:
            throw RadrootsLocationServicesError.permissionDenied("location permission is denied")
        case .unavailable:
            throw RadrootsLocationServicesError.unavailable("location services are unavailable")
        case .timeout:
            throw RadrootsLocationServicesError.timeout("current location request timed out")
        }
    }
}
