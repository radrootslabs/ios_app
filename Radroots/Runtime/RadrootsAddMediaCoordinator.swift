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
    private let blossomOrigin: URL

    init(
        roots: RadrootsAppleFileRoots,
        picker: any RadrootsMediaPicker,
        preparer: RadrootsAppleMediaPreparer,
        blossomOrigin: URL
    ) throws {
        guard let scheme = blossomOrigin.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              blossomOrigin.user == nil,
              blossomOrigin.password == nil,
              blossomOrigin.query == nil,
              blossomOrigin.fragment == nil,
              blossomOrigin.path.isEmpty || blossomOrigin.path == "/"
        else {
            throw RadrootsRuntimeFailure.local(
                operation: "add.media.configure",
                code: "ios.add.blossom_origin_invalid",
                safeMessage: "The configured media server is invalid."
            )
        }
        self.roots = roots
        self.picker = picker
        self.preparer = preparer
        self.blossomOrigin = blossomOrigin
    }

    static func production(bundleIdentifier: String, blossomOrigin: URL) throws -> Self {
        let roots = try RadrootsAppleFileRoots.appContainer(appIdentifier: bundleIdentifier)
        let fileAccess = RadrootsAppleFileAccess(roots: roots)
        return try Self(
            roots: roots,
            picker: RadrootsAppleMediaPicker(fileAccess: fileAccess),
            preparer: RadrootsAppleMediaPreparer(roots: roots),
            blossomOrigin: blossomOrigin
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
        guard let url = URL(
            string: "\(blossomOrigin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(prepared.sha256).png"
        ) else {
            throw RadrootsRuntimeFailure.local(
                operation: "add.media.prepare",
                code: "ios.add.media_url_invalid",
                safeMessage: "The media destination could not be prepared."
            )
        }
        return RadrootsPreparedMedia(
            opaqueReference: "media:\(prepared.sha256)",
            url: url.absoluteString,
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
