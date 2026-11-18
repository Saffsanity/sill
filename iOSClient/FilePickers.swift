import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import StreamProtocol

/// The Files rows' pickers (docs/files-plan.md §8.1, §8.3): the system's Files picker (SwiftUI's
/// `fileImporter`, which HostSettingsPanel shows) and Photos picker (`PhotosPickerSheet`), and what each gives
/// as DeviceFiles' sources. Neither needs a permission: each gives Sill only what the person picks. A file
/// from the Files picker is read in place under its security scope (an iCloud file downloads first, in
/// DeviceFiles); a photo or a video comes as its original (HEIC and HEVC as they are; a Live Photo's still),
/// copied into a folder of Sill's own under the outbox inside its provider's handler, since iOS deletes its
/// own copy when the handler returns, and deleted once its transfer ends. Main thread.
enum FilePickers {
    /// The Files picker's URLs as sources: each by its own name, read in place.
    static func sources(files urls: [URL]) -> [DeviceFiles.Source] {
        urls.map { DeviceFiles.Source(url: $0, name: $0.lastPathComponent, scoped: true,
                                      type: UTType(filenameExtension: $0.pathExtension)?.identifier) }
    }

    /// The Photos picker's items to the Mac: the chip says they are being got ready while each one's
    /// original loads (from iCloud, if it lives there), then they go as one transfer; if any cannot be had,
    /// none go, and the chip says which.
    static func send(_ results: [PHPickerResult], client: StreamClient) {
        guard !results.isEmpty else { return }
        let names = results.map { $0.itemProvider.suggestedName ?? "Photo" }
        client.showFilesLocally(.preparing, names: names)
        let token = client.filesLocalToken
        load(results) { sources, failed in
            // Cancelled while they loaded: nothing goes, and Sill's copies go.
            guard client.filesLocalToken == token else {
                for s in sources { DeviceFiles.deleteOwnCopy(s.url) }
                return
            }
            if let first = failed.first {
                for s in sources { DeviceFiles.deleteOwnCopy(s.url) }
                client.showFilesLocally(.stopped(reason: FileReason.cantRead.rawValue, message: nil, byPeer: false,
                                                 name: FileNames.clean(first)), names: names)
                return
            }
            client.sendFiles(sources)
        }
    }

    /// Each item as its file: its first registered type that is an image or a movie (a Live Photo's still,
    /// never its bundle), loaded and copied, named by its suggested name and that type's extension, unique
    /// in its folder. `done` on the main thread with the sources in the picker's order and the names of
    /// those that could not be had.
    static func load(_ results: [PHPickerResult], done: @escaping ([DeviceFiles.Source], [String]) -> Void) {
        let fm = FileManager.default
        let folder = DeviceFiles.outbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let group = DispatchGroup()
        let lock = NSLock()
        var slots = [DeviceFiles.Source?](repeating: nil, count: results.count)
        var failed: [String] = []
        var taken = Set<String>()
        for (i, result) in results.enumerated() {
            let provider = result.itemProvider
            let base = provider.suggestedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Photo"
            guard let type = provider.registeredTypeIdentifiers.first(where: { id in
                UTType(id).map { $0.conforms(to: .image) || $0.conforms(to: .movie) } ?? false
            }) else {
                lock.lock(); failed.append(base); lock.unlock()
                continue
            }
            let ext = UTType(type)?.preferredFilenameExtension
            group.enter()
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                defer { group.leave() }
                guard let url else { lock.lock(); failed.append(base); lock.unlock(); return }
                let fileExt = ext ?? (url.pathExtension.isEmpty ? nil : url.pathExtension)
                lock.lock()
                let wanted = FileNames.clean(fileExt.map { "\(base).\($0)" } ?? base)
                let name = FileNames.unique(wanted) { taken.contains($0.lowercased()) } ?? UUID().uuidString
                taken.insert(name.lowercased())
                lock.unlock()
                let copy = folder.appendingPathComponent(name)
                do {
                    try fm.copyItem(at: url, to: copy)   // a clone on APFS, made before the handler returns
                } catch {
                    lock.lock(); failed.append(base); lock.unlock()
                    return
                }
                lock.lock(); slots[i] = DeviceFiles.Source(url: copy, name: name, ownCopy: true, type: type); lock.unlock()
            }
        }
        group.notify(queue: .main) {
            let sources = slots.compactMap { $0 }
            if sources.isEmpty { try? fm.removeItem(at: folder) }
            done(sources, failed)
        }
    }
}

/// The system's Photos picker (PHPickerViewController), as a sheet: what the person picks comes as it is,
/// with no access to the library (no permission asked), up to `FilePolicy.maxFiles` items, in the order
/// picked. Cancel gives nothing.
struct PhotosPickerSheet: UIViewControllerRepresentable {
    let picked: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = FilePolicy.maxFiles
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(picked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let picked: ([PHPickerResult]) -> Void
        init(_ picked: @escaping ([PHPickerResult]) -> Void) { self.picked = picked }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { picked(results) }
    }
}
