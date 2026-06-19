#if DEBUG
import Foundation

enum FieldIdentityImportFailureUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_IDENTITY_IMPORT_FAILURE_PROBE"
    private static let candidateSecretKey = "RADROOTS_FIELD_IOS_UI_TEST_IDENTITY_IMPORT_FAILURE_SECRET"
    private static let defaultCandidateSecret = "0000000000000000000000000000000000000000000000000000000000000002"

    static var isRequested: Bool {
        FieldUITestHarness.string(enabledKey) == "true"
    }

    static func value(
        secureStore: FieldSecureIdentityStore,
        service: FieldRuntimeService
    ) async -> String? {
        guard isRequested else {
            return nil
        }
        let previousSecret = try? secureStore.loadSelectedSecretHex()
        let candidateSecret = FieldUITestHarness.string(candidateSecretKey) ?? defaultCandidateSecret
        var importFailed = false
        var errorContainsForcedRestore = false

        do {
            _ = try await secureStore.importSecret(
                candidateSecret,
                label: "UI Test Import Failure",
                using: service
            )
        } catch {
            importFailed = true
            errorContainsForcedRestore = error.localizedDescription.contains("Forced identity import restore failure")
        }

        let selectedSecretAfterImport = try? secureStore.loadSelectedSecretHex()
        var runtimePreviousRestored = false
        if previousSecret != nil,
           let restored = try? await secureStore.restoreStoredIdentity(
            label: "Radroots Field",
            using: service
           ) {
            runtimePreviousRestored = restored.isSelected
        }

        return [
            "previous_secret_present=\(previousSecret != nil)",
            "import_failed=\(importFailed)",
            "error_contains_forced_restore=\(errorContainsForcedRestore)",
            "selected_secret_preserved=\(selectedSecretAfterImport == previousSecret)",
            "candidate_secret_selected=\(selectedSecretAfterImport == candidateSecret)",
            "runtime_previous_restored=\(runtimePreviousRestored)"
        ].joined(separator: ";")
    }
}
#endif
