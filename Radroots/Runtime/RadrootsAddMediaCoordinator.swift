import Foundation
import RadrootsKit

struct RadrootsAddMediaSupport: Sendable, Equatable {
  let library: Bool
  let camera: Bool

  static let unavailable = Self(library: false, camera: false)
}

struct RadrootsAddBackgroundUploadReceipt: Sendable, Equatable {
  let identifier: String
  let statusCode: UInt16
  let mediaType: String?
  let contentEncoding: String?
  let body: Data
}

protocol RadrootsAddMediaHandling: Sendable {
  func support() async throws -> RadrootsAddMediaSupport
  func importImages(limit: Int) async throws -> [RadrootsPreparedMedia]
  func captureImage() async throws -> RadrootsPreparedMedia
  func open(_ media: [RadrootsPreparedMedia]) async throws -> RadrootsOpenedMedia
  func uploadInBackground(
    job: RadrootsNativeUploadJob,
    media: RadrootsPreparedMedia
  ) async throws -> RadrootsAddBackgroundUploadReceipt
  func settleBackgroundUpload(identifier: String, accepted: Bool) async throws
}

extension RadrootsAddMediaHandling {
  func uploadInBackground(
    job _: RadrootsNativeUploadJob,
    media _: RadrootsPreparedMedia
  ) async throws -> RadrootsAddBackgroundUploadReceipt {
    throw RadrootsRuntimeFailure.local(
      operation: "add.media.background",
      code: "ios.add.background_transfer_unavailable",
      safeMessage: "Background photo upload is unavailable on this device."
    )
  }

  func settleBackgroundUpload(identifier _: String, accepted _: Bool) async throws {}
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
  private let transfer: any RadrootsBackgroundTransfer

  init(
    roots: RadrootsAppleFileRoots,
    picker: any RadrootsMediaPicker,
    preparer: RadrootsAppleMediaPreparer,
    transfer: any RadrootsBackgroundTransfer
  ) {
    self.roots = roots
    self.picker = picker
    self.preparer = preparer
    self.transfer = transfer
  }

  static func production(
    bundleIdentifier: String,
    transfer: any RadrootsBackgroundTransfer
  ) throws -> Self {
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
      preparer: RadrootsAppleMediaPreparer(roots: roots),
      transfer: transfer
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

  func uploadInBackground(
    job: RadrootsNativeUploadJob,
    media: RadrootsPreparedMedia
  ) async throws -> RadrootsAddBackgroundUploadReceipt {
    guard job.expectedSHA256 == media.sha256,
      job.mediaType == media.mediaType,
      job.byteSize == media.byteSize,
      let byteSize = Int(exactly: media.byteSize),
      let remoteURL = URL(string: job.remoteURL)
    else {
      throw RadrootsRuntimeFailure.local(
        operation: "add.media.background",
        code: "ios.add.background_upload_mismatch",
        safeMessage: "The prepared photo no longer matches the authorized upload."
      )
    }
    let identifier = try Self.transferIdentifier(job: job)
    let prepared = try RadrootsApplePreparedImage(
      file: RadrootsStagedBlobReference(
        blobID: media.sha256,
        sizeBytes: byteSize,
        mediaType: media.mediaType,
        filenameHint: "\(media.sha256).png"
      ),
      sha256: media.sha256,
      width: media.width,
      height: media.height
    )
    let request = try await preparer.blossomUploadRequest(
      preparedImage: prepared,
      remoteURL: remoteURL,
      authorization: job.authorizationHeader,
      networkPolicy: remoteURL.scheme?.lowercased() == "https"
        ? .publicHTTPS : .simulatorLoopbackHTTP,
      identifier: identifier
    )
    _ = try await transfer.enqueue(request)
    return try await withTaskCancellationHandler {
      while true {
        try Task.checkCancellation()
        guard let snapshot = try await transfer.snapshot(for: identifier) else {
          throw RadrootsRuntimeFailure.local(
            operation: "add.media.background",
            code: "ios.add.background_upload_missing",
            safeMessage: "The background photo upload could not be recovered."
          )
        }
        switch snapshot.state {
        case .awaitingVerification:
          guard let response = snapshot.response,
            let statusCode = UInt16(exactly: response.statusCode),
            let body = response.body
          else {
            throw RadrootsRuntimeFailure.local(
              operation: "add.media.background",
              code: "ios.add.background_response_invalid",
              safeMessage: "The photo service returned an invalid response."
            )
          }
          return RadrootsAddBackgroundUploadReceipt(
            identifier: identifier.rawValue,
            statusCode: statusCode,
            mediaType: response.mediaType,
            contentEncoding: response.contentEncoding,
            body: body
          )
        case .failed, .interrupted, .cancelled, .expired:
          throw RadrootsRuntimeFailure.local(
            operation: "add.media.background",
            code: snapshot.errorMessage ?? "ios.add.background_upload_failed",
            safeMessage: "The background photo upload did not complete."
          )
        case .completed:
          throw RadrootsRuntimeFailure.local(
            operation: "add.media.background",
            code: "ios.add.background_upload_already_settled",
            safeMessage: "The background photo upload was already settled."
          )
        case .queued, .running:
          try await Task.sleep(for: .milliseconds(100))
        }
      }
    } onCancel: {
      Task {
        try? await self.transfer.cancel(identifier)
      }
    }
  }

  func settleBackgroundUpload(identifier: String, accepted: Bool) async throws {
    do {
      let value = try RadrootsBackgroundTransferIdentifier(identifier)
      try await transfer.settle(
        value,
        verification: accepted
          ? .accepted
          : .rejected(code: "background_transfer_rust_verification_failed")
      )
    } catch {
      throw RadrootsRuntimeFailure.local(
        operation: "add.media.background.settle",
        code: "ios.add.background_settlement_failed",
        safeMessage: "The verified photo transfer could not be finalized."
      )
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

  private static func transferIdentifier(
    job: RadrootsNativeUploadJob
  ) throws -> RadrootsBackgroundTransferIdentifier {
    try RadrootsBackgroundTransferIdentifier(
      "radroots.add.\(job.draft.id).\(job.draft.revision).\(job.operationID)"
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
        (1...40 * 1024 * 1024).contains(size)
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
