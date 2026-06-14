import Foundation
import RadrootsKit
import RadrootsKitTesting

enum FieldCaptureIntakeError: LocalizedError {
    case serviceNotReady
    case missingFileScope(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotReady:
            "Capture intake is not ready. Please retry."
        case .missingFileScope(let value):
            "Unsupported capture file scope: \(value)."
        }
    }
}

public enum FieldCaptureRecordSource: String, Codable, Equatable, Sendable {
    case libraryImport
    case cameraCapture
    case documentScan

    var displayName: String {
        switch self {
        case .libraryImport:
            "Imported photo"
        case .cameraCapture:
            "Camera photo"
        case .documentScan:
            "Scanned document"
        }
    }
}

public enum FieldCaptureRecordKind: String, Codable, Equatable, Sendable {
    case image
    case pdf
}

public enum FieldCaptureFileScope: String, Codable, Equatable, Sendable {
    case data
    case cache
    case temporary
    case logs

    init(_ scope: RadrootsFileScope) {
        switch scope {
        case .data:
            self = .data
        case .cache:
            self = .cache
        case .temporary:
            self = .temporary
        case .logs:
            self = .logs
        }
    }

    var fileScope: RadrootsFileScope {
        switch self {
        case .data:
            .data
        case .cache:
            .cache
        case .temporary:
            .temporary
        case .logs:
            .logs
        }
    }
}

public struct FieldCaptureRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    let source: FieldCaptureRecordSource
    let kind: FieldCaptureRecordKind
    let fileScope: FieldCaptureFileScope
    let fileRelativePath: String
    let mediaType: String
    let suggestedFilename: String
    let sizeBytes: UInt64
    let pixelWidth: UInt32?
    let pixelHeight: UInt32?
    let pageCount: UInt16?
    let capturedAt: Date

    var file: RadrootsFileReference {
        RadrootsFileReference(scope: fileScope.fileScope, relativePath: fileRelativePath)
    }

    var summary: String {
        if let pageCount {
            return "\(source.displayName) - \(pageCount) pages - \(suggestedFilename)"
        }
        if let pixelWidth, let pixelHeight {
            return "\(source.displayName) - \(pixelWidth)x\(pixelHeight) - \(suggestedFilename)"
        }
        return "\(source.displayName) - \(suggestedFilename)"
    }
}

public struct FieldCaptureSupportState: Equatable, Sendable {
    var photoImportAvailable: Bool
    var cameraPhotoAvailable: Bool
    var documentScannerAvailable: Bool

    static let unavailable = FieldCaptureSupportState(
        photoImportAvailable: false,
        cameraPhotoAvailable: false,
        documentScannerAvailable: false
    )
}

public enum FieldCaptureIntakeOperation: Equatable, Sendable {
    case idle
    case refreshing
    case importingPhoto
    case capturingPhoto
    case scanningDocument
}

public struct FieldCaptureIntakeState: Equatable, Sendable {
    var support: FieldCaptureSupportState
    var records: [FieldCaptureRecord]
    var operation: FieldCaptureIntakeOperation
    var lastError: String?

    static let idle = FieldCaptureIntakeState(
        support: .unavailable,
        records: [],
        operation: .idle,
        lastError: nil
    )

    var latestRecord: FieldCaptureRecord? {
        records.sorted { left, right in
            left.capturedAt > right.capturedAt
        }.first
    }
}

final class FieldCaptureIntake: @unchecked Sendable {
    private let mediaPicker: any RadrootsMediaPicker
    private let documentScanner: any RadrootsDocumentScanner
    private let fileAccess: RadrootsAppleFileAccess
    private let recordsFile = RadrootsFileReference(
        scope: .data,
        relativePath: "capture_intake/records.json"
    )
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileAccess: RadrootsAppleFileAccess,
        mediaPicker: any RadrootsMediaPicker,
        documentScanner: any RadrootsDocumentScanner
    ) {
        self.fileAccess = fileAccess
        self.mediaPicker = mediaPicker
        self.documentScanner = documentScanner
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    static func configured(bundleIdentifier: String) throws -> FieldCaptureIntake {
        let fileAccess = try FieldLocalState.fileAccess(bundleIdentifier: bundleIdentifier)
        if uiTestWasRequested {
            return try uiTestConfigured(fileAccess: fileAccess)
        }
        return FieldCaptureIntake(
            fileAccess: fileAccess,
            mediaPicker: RadrootsAppleMediaPicker(fileAccess: fileAccess),
            documentScanner: RadrootsAppleDocumentScanner(fileAccess: fileAccess)
        )
    }

    func loadRecords() throws -> [FieldCaptureRecord] {
        do {
            let result = try fileAccess.read(recordsFile, mode: .inline)
            guard case .inline(let data) = result else {
                return []
            }
            return try decoder.decode([FieldCaptureRecord].self, from: data)
        } catch let error as RadrootsAppleFileError {
            if case .notFound = error {
                return []
            }
            throw error
        }
    }

    func support() async throws -> FieldCaptureSupportState {
        let mediaSupport = try await mediaPicker.currentSupport()
        let scannerSupport = try await documentScanner.currentSupport()
        return FieldCaptureSupportState(
            photoImportAvailable: mediaSupport.importAvailable && mediaSupport.supportedImportKinds.contains(.image),
            cameraPhotoAvailable: mediaSupport.cameraCaptureAvailable && mediaSupport.supportedCaptureKinds.contains(.image),
            documentScannerAvailable: scannerSupport.interactiveScanAvailable && scannerSupport.supportedOutputKinds.contains(.pdf)
        )
    }

    func importPhoto(records: [FieldCaptureRecord]) async throws -> [FieldCaptureRecord] {
        let result = try await mediaPicker.importMedia(
            try RadrootsMediaImportRequest(
                allowedMediaKinds: [.image],
                selectionLimit: 1,
                destinationScope: .data
            )
        )
        return try append(result.items.map(record(from:)), to: records)
    }

    func capturePhoto(records: [FieldCaptureRecord]) async throws -> [FieldCaptureRecord] {
        let result = try await mediaPicker.captureMedia(
            try RadrootsMediaCaptureRequest(mediaKind: .image, destinationScope: .data)
        )
        return try append([record(from: result.item)], to: records)
    }

    func scanDocument(records: [FieldCaptureRecord]) async throws -> [FieldCaptureRecord] {
        let result = try await documentScanner.scanDocument(
            RadrootsDocumentScanRequest(outputKind: .pdf, destinationScope: .data)
        )
        return try append([record(from: result)], to: records)
    }

    private func append(_ newRecords: [FieldCaptureRecord], to records: [FieldCaptureRecord]) throws -> [FieldCaptureRecord] {
        let updated = records + newRecords
        try save(updated)
        return updated
    }

    private func save(_ records: [FieldCaptureRecord]) throws {
        try fileAccess.write(.inline(encoder.encode(records)), to: recordsFile)
    }

    private func record(from asset: RadrootsMediaAsset) -> FieldCaptureRecord {
        FieldCaptureRecord(
            id: UUID(),
            source: asset.source == .cameraCapture ? .cameraCapture : .libraryImport,
            kind: .image,
            fileScope: FieldCaptureFileScope(asset.file.scope),
            fileRelativePath: asset.file.relativePath,
            mediaType: asset.mediaType,
            suggestedFilename: asset.suggestedFilename,
            sizeBytes: asset.sizeBytes,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            pageCount: nil,
            capturedAt: asset.capturedAt
        )
    }

    private func record(from document: RadrootsScannedDocument) -> FieldCaptureRecord {
        FieldCaptureRecord(
            id: UUID(),
            source: .documentScan,
            kind: .pdf,
            fileScope: FieldCaptureFileScope(document.file.scope),
            fileRelativePath: document.file.relativePath,
            mediaType: document.mediaType,
            suggestedFilename: document.suggestedFilename,
            sizeBytes: document.sizeBytes,
            pixelWidth: nil,
            pixelHeight: nil,
            pageCount: document.pageCount,
            capturedAt: document.capturedAt
        )
    }

    private static var uiTestWasRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["RADROOTS_FIELD_IOS_UI_TEST"] == "true" ||
            ProcessInfo.processInfo.arguments.contains("--radroots-field-ios-ui-test")
    }

    private static func uiTestConfigured(fileAccess: RadrootsAppleFileAccess) throws -> FieldCaptureIntake {
        let importedAsset = try uiTestMediaAsset(
            fileAccess: fileAccess,
            source: .libraryImport,
            relativePath: "capture_intake/ui_tests/imported_photo.jpg",
            filename: "imported-field-photo.jpg",
            bytes: "radroots imported field photo".data(using: .utf8) ?? Data(),
            capturedAt: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let capturedAsset = try uiTestMediaAsset(
            fileAccess: fileAccess,
            source: .cameraCapture,
            relativePath: "capture_intake/ui_tests/camera_photo.jpg",
            filename: "camera-field-photo.jpg",
            bytes: "radroots camera field photo".data(using: .utf8) ?? Data(),
            capturedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let scannedDocument = try uiTestScannedDocument(fileAccess: fileAccess)
        let importOutcome = try uiTestMediaImportOutcome(success: RadrootsMediaImportResult(items: [importedAsset]))
        let captureOutcome = uiTestMediaCaptureOutcome(success: RadrootsMediaCaptureResult(item: capturedAsset))
        let scannerOutcome = uiTestDocumentScannerOutcome(success: scannedDocument)
        let mediaSupport = try RadrootsMediaPickerSupport(
            importAvailable: !uiTestOutcome("RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_IMPORT_OUTCOME").isUnavailable,
            cameraCaptureAvailable: !uiTestOutcome("RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_CAMERA_OUTCOME").isUnavailable,
            supportedImportKinds: [.image],
            supportedCaptureKinds: [.image],
            multipleSelectionSupported: false
        )
        let scannerSupport = try RadrootsDocumentScannerSupport(
            interactiveScanAvailable: !uiTestOutcome("RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_SCANNER_OUTCOME").isUnavailable,
            multiPageSupported: true,
            supportedOutputKinds: [.pdf]
        )
        return FieldCaptureIntake(
            fileAccess: fileAccess,
            mediaPicker: RadrootsFakeMediaPicker(
                support: mediaSupport,
                importOutcome: importOutcome,
                captureOutcome: captureOutcome
            ),
            documentScanner: RadrootsFakeDocumentScanner(
                support: scannerSupport,
                scanOutcome: scannerOutcome
            )
        )
    }

    private static func uiTestMediaAsset(
        fileAccess: RadrootsAppleFileAccess,
        source: RadrootsMediaSource,
        relativePath: String,
        filename: String,
        bytes: Data,
        capturedAt: Date
    ) throws -> RadrootsMediaAsset {
        let file = RadrootsFileReference(scope: .data, relativePath: relativePath)
        try fileAccess.write(.inline(bytes), to: file)
        return try RadrootsMediaAsset(
            source: source,
            kind: .image,
            file: file,
            mediaType: "image/jpeg",
            suggestedFilename: filename,
            sizeBytes: UInt64(bytes.count),
            pixelWidth: 1200,
            pixelHeight: 900,
            capturedAt: capturedAt
        )
    }

    private static func uiTestScannedDocument(fileAccess: RadrootsAppleFileAccess) throws -> RadrootsScannedDocument {
        let bytes = Data("%PDF-1.7\n% radroots field scan\n".utf8)
        let file = RadrootsFileReference(
            scope: .data,
            relativePath: "capture_intake/ui_tests/scanned_document.pdf"
        )
        try fileAccess.write(.inline(bytes), to: file)
        return try RadrootsScannedDocument(
            file: file,
            outputKind: .pdf,
            suggestedFilename: "field-scan.pdf",
            mediaType: "application/pdf",
            pageCount: 2,
            sizeBytes: UInt64(bytes.count),
            capturedAt: Date(timeIntervalSinceReferenceDate: 3_000)
        )
    }

    private static func uiTestMediaImportOutcome(
        success: RadrootsMediaImportResult
    ) throws -> Result<RadrootsMediaImportResult, RadrootsCaptureIntakeError> {
        try uiTestResult(
            key: "RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_IMPORT_OUTCOME",
            success: success
        )
    }

    private static func uiTestMediaCaptureOutcome(
        success: RadrootsMediaCaptureResult
    ) -> Result<RadrootsMediaCaptureResult, RadrootsCaptureIntakeError> {
        do {
            return try uiTestResult(
                key: "RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_CAMERA_OUTCOME",
                success: success
            )
        } catch {
            return .failure(.permanentFailure(error.localizedDescription))
        }
    }

    private static func uiTestDocumentScannerOutcome(
        success: RadrootsScannedDocument
    ) -> Result<RadrootsScannedDocument, RadrootsCaptureIntakeError> {
        do {
            return try uiTestResult(
                key: "RADROOTS_FIELD_IOS_UI_TEST_CAPTURE_SCANNER_OUTCOME",
                success: success
            )
        } catch {
            return .failure(.permanentFailure(error.localizedDescription))
        }
    }

    private static func uiTestResult<T>(
        key: String,
        success: T
    ) throws -> Result<T, RadrootsCaptureIntakeError> {
        let outcome = uiTestOutcome(key)
        switch outcome {
        case .success:
            return .success(success)
        case .cancelled:
            return .failure(.userCancelled("Capture was cancelled."))
        case .denied:
            return .failure(.permissionDenied("Capture permission is denied."))
        case .unavailable:
            return .failure(.unavailable("Capture is unavailable."))
        case .transientFailure:
            return .failure(.transientFailure("Capture failed. Please retry."))
        }
    }

    private static func uiTestOutcome(_ key: String) -> FieldCaptureUITestOutcome {
        FieldCaptureUITestOutcome(
            rawValue: ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ) ?? .success
    }
}

private enum FieldCaptureUITestOutcome: String {
    case success
    case cancelled
    case denied
    case unavailable
    case transientFailure = "transient_failure"

    var isUnavailable: Bool {
        self == .unavailable
    }
}
