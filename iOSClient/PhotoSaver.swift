import Foundation
import Photos
import UniformTypeIdentifiers

/// Save to Photos (docs/files-plan.md §8.4): the photos and videos of a transfer from the Mac, kept in Documents ›
/// From ‹Mac›, added to the Photos library with add-only access (PHAccessLevel.addOnly), never read access: Sill
/// never sees the library. The access is asked the first time (NSPhotoLibraryAddUsageDescription), and as the
/// device's Save Photos and Videos to Photos switch goes on. Each file is its own change, so one Photos refuses (a
/// format it does not take) is named and the rest still go.
enum PhotoSaver {
    /// Whether add-only access is given now, or may still be asked for.
    static var mayAsk: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited || status == .notDetermined
    }

    /// Asks for add-only access (once; later calls answer at once): whether it is given. `done` on the main thread.
    static func ask(_ done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async { done(status == .authorized || status == .limited) }
        }
    }

    /// `urls` into Photos, one after another: `.saved(n)`, `.denied`, or `.failed(name)` for the first Photos refused
    /// (the others went). `done` on the main thread.
    static func save(_ urls: [URL], done: @escaping (DeviceFilesCopy.PhotosResult) -> Void) {
        ask { given in
            guard given else { done(.denied); return }
            next(urls[...], saved: 0, failed: nil, done: done)
        }
    }

    private static func next(_ rest: ArraySlice<URL>, saved: Int, failed: String?, done: @escaping (DeviceFilesCopy.PhotosResult) -> Void) {
        guard let url = rest.first else {
            done(failed.map { .failed($0) } ?? .saved(saved))
            return
        }
        let video = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: video ? .video : .photo, fileURL: url, options: nil)
        }, completionHandler: { ok, _ in
            DispatchQueue.main.async {
                next(rest.dropFirst(), saved: saved + (ok ? 1 : 0), failed: failed ?? (ok ? nil : url.lastPathComponent), done: done)
            }
        })
    }
}
