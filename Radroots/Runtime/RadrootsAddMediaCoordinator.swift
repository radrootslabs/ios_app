import Foundation
import RadrootsKit

struct RadrootsAddMediaSupport: Sendable, Equatable {
    let library: Bool
    let camera: Bool

    static let unavailable = Self(library: false, camera: false)
}

protocol RadrootsAddMediaHandling: Sendable {
    func support() async throws -> RadrootsAddMediaSupport
    func importImages(limit: Int) async throws -> [RadrootsPreparedMedia]
    func captureImage() async throws -> RadrootsPreparedMedia
    func open(_ media: [RadrootsPreparedMedia]) async throws -> RadrootsOpenedMedia
}

final class RadrootsOpenedMedia: @unchecked Sendable {
    let handles: [RadrootsPreparedMediaHandle]
    private var files: [FileHandle]

    init(handles: [RadrootsPreparedMediaHandle], files: [FileHandle]) {
        self.handles = handles
        self.files = files
    }

    deinit {
        close()
    }

    func close() {
        let active = files
        files.removeAll()
        for file in active {
            try? file.close()
        }
    }
}

actor RadrootsAddMediaCoordinator: RadrootsAddMediaHandling {
    private let roots: RadrootsAppleFileRoots
    private let picker: any RadrootsMediaPicker
    private let preparer: RadrootsAppleMediaPreparer

    init(
        roots: RadrootsAppleFileRoots,
        picker: any RadrootsMediaPicker,
        preparer: RadrootsAppleMediaPreparer
    ) {
        self.roots = roots
        self.picker = picker
        self.preparer = preparer
    }

    static func production(bundleIdentifier: String) throws -> Self {
        let roots = try RadrootsAppleFileRoots.appContainer(appIdentifier: bundleIdentifier)
        let fileAccess = RadrootsAppleFileAccess(roots: roots)
        let picker: any RadrootsMediaPicker
        #if DEBUG
            if let mediaFile = try RadrootsRemoteQualificationEnvironment.current()?.mediaFile {
                picker = RadrootsRemoteQualificationMediaPicker(
                    roots: roots,
                    file: mediaFile
                )
            } else {
                picker = RadrootsAppleMediaPicker(fileAccess: fileAccess)
            }
        #else
            picker = RadrootsAppleMediaPicker(fileAccess: fileAccess)
        #endif
        return Self(
            roots: roots,
            picker: picker,
            preparer: RadrootsAppleMediaPreparer(roots: roots)
        )
    }

    func support() async throws -> RadrootsAddMediaSupport {
        let value = try await picker.currentSupport()
        return RadrootsAddMediaSupport(
            library: value.importAvailable && value.supportedImportKinds.contains(.image),
            camera: value.cameraCaptureAvailable && value.supportedCaptureKinds.contains(.image)
        )
    }

    func importImages(limit: Int) async throws -> [RadrootsPreparedMedia] {
        let result = try await picker.importMedia(
            RadrootsMediaImportRequest(
                allowedMediaKinds: [.image],
                selectionLimit: min(max(limit, 1), 20),
                destinationScope: .cache
            )
        )
        var prepared: [RadrootsPreparedMedia] = []
        for asset in result.items {
            try await prepared.append(prepare(asset))
        }
        return prepared
    }

    func captureImage() async throws -> RadrootsPreparedMedia {
        let result = try await picker.captureMedia(
            RadrootsMediaCaptureRequest(mediaKind: .image, destinationScope: .cache)
        )
        return try await prepare(result.item)
    }

    func open(_ media: [RadrootsPreparedMedia]) throws -> RadrootsOpenedMedia {
        var files: [FileHandle] = []
        var handles: [RadrootsPreparedMediaHandle] = []
        do {
            for item in media {
                guard item.opaqueReference == "media:\(item.sha256)",
                      item.mediaType == "image/png",
                      let byteSize = Int(exactly: item.byteSize)
                else {
                    throw RadrootsRuntimeFailure.local(
                        operation: "add.media.open",
                        code: "ios.add.media_reference_invalid",
                        safeMessage: "A prepared photo is no longer available."
                    )
                }
                let blob = try RadrootsStagedBlobReference(
                    blobID: item.sha256,
                    sizeBytes: byteSize,
                    mediaType: item.mediaType,
                    filenameHint: "\(item.sha256).png"
                )
                let file = try FileHandle(forReadingFrom: roots.stagedBlobURL(for: blob))
                files.append(file)
                handles.append(
                    RadrootsPreparedMediaHandle(
                        media: item,
                        fileDescriptor: UInt64(file.fileDescriptor)
                    )
                )
            }
            return RadrootsOpenedMedia(handles: handles, files: files)
        } catch {
            for file in files {
                try? file.close()
            }
            throw error
        }
    }

    private func prepare(_ asset: RadrootsMediaAsset) async throws -> RadrootsPreparedMedia {
        let prepared = try await preparer.prepareImage(
            RadrootsAppleImagePreparationRequest(source: .file(asset.file))
        )
        return RadrootsPreparedMedia(
            opaqueReference: "media:\(prepared.sha256)",
            remoteURL: nil,
            sha256: prepared.sha256,
            mediaType: "image/png",
            byteSize: UInt64(prepared.file.sizeBytes),
            width: prepared.width,
            height: prepared.height,
            alt: "Farm photo",
            preparedAtUnixSeconds: UInt64(Date().timeIntervalSince1970)
        )
    }
}

#if DEBUG
    private actor RadrootsRemoteQualificationMediaPicker: RadrootsMediaPicker {
        private let roots: RadrootsAppleFileRoots
        private let file: RadrootsFileReference

        init(roots: RadrootsAppleFileRoots, file: RadrootsFileReference) {
            self.roots = roots
            self.file = file
        }

        func currentSupport() async throws -> RadrootsMediaPickerSupport {
            try RadrootsMediaPickerSupport(
                importAvailable: true,
                cameraCaptureAvailable: false,
                supportedImportKinds: [.image],
                supportedCaptureKinds: [],
                multipleSelectionSupported: false
            )
        }

        func importMedia(
            _ request: RadrootsMediaImportRequest
        ) async throws -> RadrootsMediaImportResult {
            guard request.allowedMediaKinds == [.image], request.selectionLimit >= 1 else {
                throw RadrootsCaptureIntakeError.invalidRequest(
                    "remote qualification accepts one image"
                )
            }
            let url = try roots.resolvedURL(for: file)
            let values = try url.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  (1 ... 40 * 1024 * 1024).contains(size)
            else {
                throw RadrootsCaptureIntakeError.unavailable(
                    "remote qualification image is unavailable"
                )
            }
            let asset = try RadrootsMediaAsset(
                source: .libraryImport,
                kind: .image,
                file: file,
                mediaType: "image/png",
                suggestedFilename: "input.png",
                sizeBytes: UInt64(size),
                capturedAt: Date()
            )
            return try RadrootsMediaImportResult(items: [asset])
        }

        func captureMedia(
            _: RadrootsMediaCaptureRequest
        ) async throws -> RadrootsMediaCaptureResult {
            throw RadrootsCaptureIntakeError.unavailable(
                "camera capture is outside remote qualification"
            )
        }
    }
#endif
