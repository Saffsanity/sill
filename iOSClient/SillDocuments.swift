import Foundation

/// The one owner of Sill's Documents folder (the overview's §2.3), which the Files app shows as On My ‹iPad› › Sill
/// (UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace in both Info.plists): nothing else in the app names
/// `documentDirectory`. Files from a Mac go into From ‹Mac› (DeviceFilesCopy.folderName: the Mac's name cleaned as a
/// file's), protected `complete`; they are staged until whole and checked in Library/Application Support/Sill/Incoming,
/// on the same volume and never shown. A file another app opened in Sill as a copy waits in Documents/Inbox, where iOS
/// puts it. The recordings of #284 take their own folder here (`Sill Recordings`, `completeUnlessOpen`) when they come.
/// Foundation only: nothing here is made until a transfer needs it (DeviceInbox).
enum SillDocuments {
    /// Documents: On My ‹iPad› › Sill.
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
    }

    /// Where iOS puts a copy of another app's file opened in Sill (the share sheet's Sill without in-place opening).
    static var inbox: URL { documents.appendingPathComponent("Inbox", isDirectory: true) }

    /// Files from `mac`: Documents › From ‹Mac›.
    static func fromMac(_ mac: String) -> URL {
        documents.appendingPathComponent(DeviceFilesCopy.folderName(mac: mac), isDirectory: true)
    }

    /// Where files from a Mac are written until whole and checked (DeviceInbox).
    static var incoming: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Sill/Incoming", isDirectory: true)
    }
}
