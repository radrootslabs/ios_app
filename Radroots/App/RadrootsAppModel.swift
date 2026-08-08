import Foundation

@MainActor
final class RadrootsAppModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case identityRequired
        case running(RadrootsRuntimeSnapshot)
        case failed(RadrootsRuntimeFailure)
        case stopped
    }

    @Published private(set) var phase: Phase = .starting

    private let runtimeClient: RadrootsRuntimeClient
    private let configuration: RadrootsRuntimeLaunchConfiguration?

    init(
        runtimeClient: RadrootsRuntimeClient = .production(),
        configuration: RadrootsRuntimeLaunchConfiguration? = nil
    ) {
        self.runtimeClient = runtimeClient
        self.configuration = configuration
    }

    func start() async {
        guard let configuration else {
            phase = .identityRequired
            return
        }
        phase = .starting
        do {
            phase = try await .running(runtimeClient.start(configuration: configuration))
        } catch let RadrootsRuntimeClientError.startup(failure) {
            phase = .failed(failure)
        } catch {
            phase = .failed(
                .local(
                    operation: "app.start",
                    code: "ios.app.start_failed",
                    safeMessage: "Radroots could not start."
                )
            )
        }
    }

    func retry() async {
        await start()
    }

    func stop() async {
        do {
            _ = try await runtimeClient.stop()
            phase = .stopped
        } catch let RadrootsRuntimeClientError.shutdown(failure) {
            phase = .failed(failure)
        } catch {
            phase = .failed(
                .local(
                    operation: "app.stop",
                    code: "ios.app.stop_failed",
                    safeMessage: "Radroots could not finish shutting down."
                )
            )
        }
    }
}
