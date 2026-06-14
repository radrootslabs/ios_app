import RadrootsKit
import SwiftUI

struct RelaysView: View {
    @EnvironmentObject private var app: AppState
    @State private var preparedExport: RadrootsPreparedExportDocument?
    @State private var activeExport: RadrootsPreparedExportDocument?
    @State private var importRequest: RadrootsDocumentImportRequest?
    @State private var fileAccess: RadrootsAppleFileAccess?
    @State private var importedRelays: [String] = []
    @State private var documentMessage: String?
    @State private var documentError: String?

    private var configuredRelays: [String] {
        (try? RelaySettings.relays()) ?? []
    }

    var body: some View {
        List {
            Section("Relays") {
                RelayMetricRow(
                    label: "Connected",
                    systemImage: "dot.radiowaves.left.and.right",
                    value: app.relayConnectedCount,
                    accessibilityID: "field_ios.relays.connected_count"
                )
                RelayMetricRow(
                    label: "Connecting",
                    systemImage: "antenna.radiowaves.left.and.right",
                    value: app.relayConnectingCount,
                    accessibilityID: "field_ios.relays.connecting_count"
                )
                if let last = app.relayLastError {
                    Text(last)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("field_ios.relays.last_error")
                }
            }

            Section("Configured Relays") {
                if configuredRelays.isEmpty {
                    Text("No relays configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(configuredRelays, id: \.self) { url in
                        Text(url)
                            .font(.callout.monospaced())
                            .accessibilityIdentifier("field_ios.relays.configured_url")
                    }
                }
            }

            Section("Document Interchange") {
                Button {
                    prepareRelayExport()
                } label: {
                    Label("Export Relay Config", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("field_ios.relays.export")

                Button {
                    prepareRelayImport()
                } label: {
                    Label("Import Relay Config", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("field_ios.relays.import")

                if let documentMessage {
                    Text(documentMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("field_ios.relays.document_status")
                }
                if let documentError {
                    Text(documentError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .accessibilityIdentifier("field_ios.relays.document_error")
                }
            }

            if !importedRelays.isEmpty {
                Section("Imported Relays") {
                    ForEach(importedRelays, id: \.self) { url in
                        Text(url)
                            .font(.callout.monospaced())
                            .accessibilityIdentifier("field_ios.relays.imported_url")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .inlineNavigationTitle("Relays")
        .task {
            fileAccess = try? app.documentFileAccess()
        }
        .radrootsDocumentExporter(preparedExport: $preparedExport) { result in
            handleRelayExportCompletion(result)
        }
        .background {
            if let fileAccess {
                Color.clear.radrootsDocumentImporter(
                    request: $importRequest,
                    fileAccess: fileAccess
                ) { result in
                    handleRelayImportCompletion(result)
                }
            }
        }
        .accessibilityIdentifier("field_ios.relays")
    }

    private func prepareRelayExport() {
        documentMessage = nil
        documentError = nil
        do {
            let export = try app.prepareRelayConfigDocumentExport()
            activeExport = export
            preparedExport = export
        } catch {
            documentError = error.localizedDescription
        }
    }

    private func prepareRelayImport() {
        documentMessage = nil
        documentError = nil
        do {
            if fileAccess == nil {
                fileAccess = try app.documentFileAccess()
            }
            importRequest = try RadrootsDocumentImportRequest(
                allowedContentKinds: [.json],
                allowsMultipleSelection: false,
                destinationScope: .temporary
            )
        } catch {
            documentError = error.localizedDescription
        }
    }

    private func handleRelayExportCompletion(_ result: Result<RadrootsExportDocumentResult, Error>) {
        if let activeExport {
            app.releasePreparedDocumentExport(activeExport)
        }
        activeExport = nil
        switch result {
        case .success(let exportResult):
            documentMessage = "Exported \(exportResult.exportedFilename)"
            documentError = nil
        case .failure(let error):
            documentError = error.localizedDescription
        }
    }

    private func handleRelayImportCompletion(_ result: Result<RadrootsDocumentImportResult, Error>) {
        do {
            let importResult = try result.get()
            guard let document = importResult.documents.first else {
                throw FieldDocumentInterchangeError.invalidRelayConfigDocument
            }
            importedRelays = try app.importedRelayConfig(from: document)
            documentMessage = "Imported \(importedRelays.count) relay config entries"
            documentError = nil
        } catch {
            documentError = error.localizedDescription
        }
    }
}

private struct RelayMetricRow: View {
    let label: String
    let systemImage: String
    let value: UInt32
    let accessibilityID: String

    var body: some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text("\(value)")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
        .accessibilityIdentifier(accessibilityID)
    }
}
