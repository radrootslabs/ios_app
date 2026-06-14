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
        request: RadrootsCurrentLocationRequest = try! RadrootsCurrentLocationRequest(
            timeoutSeconds: 10,
            desiredAccuracyMeters: 100,
            maximumCachedReadingAgeSeconds: 30
        )
    ) {
        self.locationServices = locationServices
        self.request = request
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
}
