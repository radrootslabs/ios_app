import Foundation
import RadrootsKit

enum FieldDocumentInterchangeUITestProbe {
    private static let enabledKey = "RADROOTS_FIELD_IOS_UI_TEST_DOCUMENT_INTERCHANGE_PROBE"
    private static let importFixture = RadrootsFileReference(
        scope: .temporary,
        relativePath: "ui_tests/document_interchange/relay_import.json"
    )
    private static let invalidImportFixture = RadrootsFileReference(
        scope: .temporary,
        relativePath: "ui_tests/document_interchange/invalid_relay_import.json"
    )

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[enabledKey] == "true"
    }

    static func startupValue(
        bundleIdentifier: String,
        infoJSONString: String,
        relays: [String],
        connectedCount: UInt32,
        connectingCount: UInt32,
        lastError: String?
    ) throws -> String? {
        guard isRequested else {
            return nil
        }
        let interchange = try FieldDocumentInterchange(bundleIdentifier: bundleIdentifier)
        let fileAccess = try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier)
        let diagnosticsExport = try interchange.prepareDiagnosticsExport(
            infoJSONString: infoJSONString,
            relays: relays,
            connectedCount: connectedCount,
            connectingCount: connectingCount,
            lastError: lastError
        )
        let diagnosticsFileExists = try fileAccess.preparedExportExists(diagnosticsExport)
        try fileAccess.releasePreparedExport(diagnosticsExport)
        let diagnosticsReleaseRemovedFile = !(try fileAccess.preparedExportExists(diagnosticsExport))
        let relayExport = try interchange.prepareRelayConfigExport(relays: relays)
        let relayExportFileExists = try fileAccess.preparedExportExists(relayExport)
        try fileAccess.releasePreparedExport(relayExport)
        try fileAccess.write(
            .inline(relayImportFixtureData()),
            to: importFixture
        )
        let importedRelays = try interchange.importedRelayConfig(from: importFixture)
        try fileAccess.write(
            .inline(invalidRelayImportFixtureData()),
            to: invalidImportFixture
        )
        let rejectedInvalidImport = invalidImportWasRejected(interchange)
        let shareRequest = try interchange.publicPostShareRequest(content: "  public field update  ")
        let shareTextTrimmed = shareRequest.items == [.text("public field update")]
        return [
            "diagnostics_filename=\(diagnosticsExport.suggestedFilename)",
            "diagnostics_media_type=\(diagnosticsExport.mediaType ?? "")",
            "diagnostics_file_exists=\(diagnosticsFileExists)",
            "diagnostics_release_removed_file=\(diagnosticsReleaseRemovedFile)",
            "relay_export_filename=\(relayExport.suggestedFilename)",
            "relay_export_media_type=\(relayExport.mediaType ?? "")",
            "relay_export_file_exists=\(relayExportFileExists)",
            "relay_import_count=\(importedRelays.count)",
            "relay_import_contains_production=\(importedRelays.contains("wss://radroots.org"))",
            "relay_import_rejected_invalid=\(rejectedInvalidImport)",
            "share_subject=\(shareRequest.subject ?? "")",
            "share_text_trimmed=\(shareTextTrimmed)"
        ].joined(separator: ";")
    }

    private static func invalidImportWasRejected(_ interchange: FieldDocumentInterchange) -> Bool {
        do {
            _ = try interchange.importedRelayConfig(from: invalidImportFixture)
            return false
        } catch {
            return true
        }
    }

    private static func relayImportFixtureData() -> Data {
        Data(
            """
            {
              "format": "radroots_field_ios_relay_config_v1",
              "relays": [
                "wss://radroots.org",
                "ws://127.0.0.1:8080",
                "wss://radroots.org"
              ]
            }
            """.utf8
        )
    }

    private static func invalidRelayImportFixtureData() -> Data {
        Data(
            """
            {
              "format": "radroots_field_ios_relay_config_v1",
              "relays": [
                "https://radroots.org"
              ]
            }
            """.utf8
        )
    }
}
