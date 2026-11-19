import Foundation

/// The one owner of Sill's Documents folder on the device (docs/recording-plan.md, Security; the next features'
/// overview, §2.3). Both Info.plists set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, so
/// everything in Documents shows in the Files app (On My iPad › Sill) and in Finder over the cable: only the
/// folders named here go there, each with its own data protection, and nothing else of Sill's (the device key,
/// the saved Macs, the tile pictures) ever can. `Tests/checks/recording` fails if any other file of the iOS app
/// names the Documents directory.
///
/// - Sill Recordings (#284): the stream's movies. `completeUnlessOpen`: readable only while the device is
///   unlocked, and a movie open at the lock may still be finished. Ordinary documents otherwise: in the device's
///   backups, deleted with Sill (decision 10).
/// - The files feature adds its From ‹Mac› folder here (`complete`), when it lands.
///
/// Foundation only. The recorder takes its folder from its caller, so the recording rig on the Mac never writes
/// into a Documents folder.
enum SillDocuments {
    enum Folder: Equatable {
        /// "Sill Recordings": the recordings of the stream.
        case recordings
    }

    /// The folder's name in Files.
    static func name(_ folder: Folder) -> String {
        switch folder {
        case .recordings: return "Sill Recordings"
        }
    }

    /// The data protection of the folder and of every file written into it.
    static func protection(_ folder: Folder) -> FileProtectionType {
        switch folder {
        case .recordings: return .completeUnlessOpen
        }
    }

    /// Where the folder is: Documents/‹name›.
    static func url(_ folder: Folder) -> URL {
        URL.documentsDirectory.appending(path: name(folder), directoryHint: .isDirectory)
    }

    /// The folder, made with its protection when it is not there yet.
    static func make(_ folder: Folder) throws -> URL {
        let url = url(folder)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: protection(folder)])
        return url
    }

    /// Gives a file in `folder` the folder's protection (a movie AVFoundation made there).
    static func protect(_ file: URL, in folder: Folder) {
        try? FileManager.default.setAttributes([.protectionKey: protection(folder)], ofItemAtPath: file.path)
    }

    /// The free space of the volume Documents is on, for important usage (the recording's space rule: the privacy
    /// manifest's DiskSpace, E174.1 and 85F4.1; the value never leaves the device); nil when it cannot be read.
    /// DEBUG `-SillRecordingSpace <bytes>` says that many instead.
    static func availableCapacity() -> Int64? {
        #if DEBUG
        let fake = UserDefaults.standard.double(forKey: "SillRecordingSpace")
        if fake > 0 { return Int64(fake) }
        #endif
        let values = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
