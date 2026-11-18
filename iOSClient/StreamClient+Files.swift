import Foundation
import UIKit
import UniformTypeIdentifiers
import StreamProtocol

/// A file shared into Sill from another app (the share sheet, Open In), waiting for the person's Send while a
/// session takes files, or for one to (`FilesShared.wait`).
struct FilesShared: Equatable {
    let sources: [DeviceFiles.Source]
    /// When it came (systemUptime).
    let at: Double
    var names: [String] { sources.map { FileNames.clean($0.name) } }
    /// How long a shared file waits for a session that takes files.
    static let wait = 600.0
}

// Files and photos, this device's side of the session (docs/files-plan.md §8): the Mac's word (`files` in its
// window list, `sessionPaired` in kind 16) decides what the Files rows offer (FilePolicy.deviceOffers); the rows'
// pickers, a file shared into Sill and the share sheet's question hand sources to DeviceFiles, which sends them
// on the session's connection; its snapshots come back here for the chip, the rows, VoiceOver, the background
// task that lets a transfer outlast Sill leaving the screen for a while, the device's auto-lock and the moves a
// transfer holds. The device takes no file from the Mac in this build: its hello says nothing of files, so the
// Mac never offers it one.
//
// Everything here is main thread.
extension StreamClient {
    private var macWord: String { macName.isEmpty ? "the Mac" : macName }

    /// What the Files rows and the share sheet's question offer now.
    var filesOffering: FilePolicy.Offering { filesOffering(ignoringLocal: false) }

    /// `ignoringLocal`: the Photos picker's items still loading (`showFilesLocally`, before DeviceFiles has
    /// them) do not count as a transfer of this device's: the send they lead to is theirs.
    private func filesOffering(ignoringLocal: Bool) -> FilePolicy.Offering {
        let sending = fileOut.map { !$0.isOver && !(ignoringLocal && $0.serial == OutgoingFiles.localSerial) } ?? false
        return FilePolicy.deviceOffers(connected: connected, hostFiles: hostFiles, hostVersion: hostVersion, locked: macLocked,
                                       sessionPaired: settings.host?.sessionPaired, sending: sending)
    }

    /// Each window list's `files`: a file shared into Sill that waited for such a session is asked about now.
    func hostFilesChanged(_ value: Int?) {
        if hostFiles != value { hostFiles = value }
        updateFilesContext()
    }

    /// The sender's context: away from home (the remote door), the Mac's report of this device's link.
    func updateFilesContext() {
        let away = remoteRoute != nil
        let behind = settings.host?.link.map { $0.state == LinkReport.behind || $0.state == LinkReport.stalled } ?? false
        deviceFiles.update(DeviceFiles.Context(away: away, linkBehind: behind))
    }

    // MARK: Sending

    /// The person picked files or photos (the rows' pickers) or said Send to a shared file: one transfer on
    /// the session's connection. Dropped, Sill's own copies with it, when the session no longer takes files
    /// (a pick that finished after the Mac locked or the session ended).
    func sendFiles(_ sources: [DeviceFiles.Source]) {
        guard !sources.isEmpty else { return }
        guard filesOffering(ignoringLocal: true) == .yes, let c = connection else {
            for s in sources where s.ownCopy { DeviceFiles.deleteOwnCopy(s.url) }
            filesDropped()
            #if DEBUG
            print("files: \(sources.count) picked, not sent: the session offers \(filesOffering)")
            #endif
            return
        }
        updateFilesContext()
        deviceFiles.send(sources, on: c)
        noteAction()
        #if DEBUG
        print("files: sending \(sources.count) \(sources.count == 1 ? "file" : "files") to the Mac")
        #endif
    }

    /// The chip's Cancel.
    func cancelFiles() {
        deviceFiles.cancel()
        noteAction()
    }

    /// Something to show before DeviceFiles has a transfer: the Photos picker's items loading (`preparing`), or
    /// what could not be had of them (a stop with its reason), as the chip shows a transfer.
    func showFilesLocally(_ phase: OutgoingFiles.Phase, names: [String]) {
        let s = OutgoingFiles(serial: OutgoingFiles.localSerial, phase: phase, names: names, total: 0, acked: 0,
                              since: ProcessInfo.processInfo.systemUptime)
        fileSnapshot(s)
    }

    /// A pick that never became a transfer (the session no longer took files, or one of this device's had
    /// just started): the Photos picker's own "getting ready" goes, so nothing waits for it.
    func filesDropped() {
        guard let out = fileOut, out.serial == OutgoingFiles.localSerial, !out.isOver else { return }
        fileOut = nil
        endFilesBackgroundTask()
    }

    /// A snapshot of the transfer (DeviceFiles, or `showFilesLocally`): the chip and the rows, what
    /// VoiceOver hears at its start and end, the background task while it runs, the auto-lock hold, and at
    /// its end the moves it held.
    func fileSnapshot(_ s: OutgoingFiles) {
        let was = fileOut
        fileOut = s
        fileOutExpiry?.cancel()
        fileOutExpiry = nil
        let newPhase = was?.serial != s.serial || !Self.samePhase(was?.phase, s.phase)
        if newPhase, let words = DeviceFilesCopy.announcement(s, mac: macWord, device: Self.deviceWord) {
            UIAccessibility.post(notification: .announcement, argument: words)
        }
        if s.isOver {
            endFilesBackgroundTask()
            if newPhase, UIDevice.current.userInterfaceIdiom == .phone {
                UINotificationFeedbackGenerator().notificationOccurred(DeviceFilesCopy.warns(s) ? .warning : .success)
            }
            let serial = s.serial
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.fileOut?.serial == serial, self.fileOut?.isOver == true else { return }
                self.fileOut = nil
            }
            fileOutExpiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + DeviceFilesCopy.resultLifetime, execute: work)
            if OutgoingFiles.holdsMoves(was) { filesMovesResume() }
            #if DEBUG
            print("files: \(DeviceFilesCopy.title(s, mac: "the Mac", device: Self.deviceWord))")
            #endif
        } else {
            beginFilesBackgroundTask()
            lastFileProgressAt = ProcessInfo.processInfo.systemUptime
            if was?.acked != s.acked || newPhase { DeviceIdleTimer.shared.used() }
        }
    }

    private static func samePhase(_ a: OutgoingFiles.Phase?, _ b: OutgoingFiles.Phase) -> Bool {
        switch (a, b) {
        case (.preparing?, .preparing), (.offering?, .offering), (.sending?, .sending), (.finishing?, .finishing): return true
        case (.done?, .done), (.stopped?, .stopped): return a == b
        default: return false
        }
    }

    /// While a transfer runs, Sill leaving the screen keeps it going for the time iOS gives a background
    /// task (about 30 s); when that ends, the transfer stops `background`, and the chip says so when Sill
    /// comes back. With Picture in Picture showing, Sill runs and the transfer goes on.
    private func beginFilesBackgroundTask() {
        guard filesBackgroundTask == .invalid else { return }
        filesBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Sill files") { [weak self] in
            guard let self else { return }
            self.deviceFiles.stop(.background, tellPeer: true)
            self.endFilesBackgroundTask()
        }
    }

    private func endFilesBackgroundTask() {
        guard filesBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(filesBackgroundTask)
        filesBackgroundTask = .invalid
    }

    /// The session ended: its transfer with it (`lost`; the Mac deletes what it had when the connection
    /// goes). The chip's last word stays for its moment; a shared file keeps waiting for the next session.
    func filesSessionEnded() {
        deviceFiles.stop(.lost, tellPeer: false)
        hostFiles = nil
        lastFileProgressAt = nil
    }

    // MARK: A file shared into Sill

    /// A file another app opened in Sill (the share sheet's Sill, Open In): its own copy when iOS made one
    /// (the app's Inbox), moved to the outbox; else the original, read in place under its security scope.
    /// While a session takes files the chip asks "Send ‹name› to ‹Mac›?"; else it waits `FilesShared.wait`
    /// for one, and the connect screen's line says so.
    func fileShared(_ url: URL) {
        let fm = FileManager.default
        let name = url.lastPathComponent
        var source = DeviceFiles.Source(url: url, name: name, scoped: true, type: UTType(filenameExtension: url.pathExtension)?.identifier)
        let inbox = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox", isDirectory: true)
        if let inbox, url.standardizedFileURL.path.hasPrefix(inbox.standardizedFileURL.path + "/") {
            let folder = DeviceFiles.outbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let moved = folder.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.moveItem(at: url, to: moved)
                source = DeviceFiles.Source(url: moved, name: name, ownCopy: true, type: source.type)
            } catch {
                try? fm.removeItem(at: url)
                showFilesLocally(.stopped(reason: FileReason.cantRead.rawValue, message: nil, byPeer: false, name: FileNames.clean(name)), names: [name])
                return
            }
        }
        if let old = filesShared { dropShared(old) }
        filesShared = FilesShared(sources: [source], at: ProcessInfo.processInfo.systemUptime)
        filesSharedExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let shared = self.filesShared else { return }
            self.dropShared(shared)
            self.filesShared = nil
        }
        filesSharedExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FilesShared.wait, execute: work)
        #if DEBUG
        print("files: a file shared into Sill (\(source.ownCopy ? "Sill's own copy" : "in place")); the session offers \(filesOffering)")
        #endif
    }

    /// The share question's Send.
    func sendShared() {
        guard let shared = filesShared else { return }
        filesShared = nil
        filesSharedExpiry?.cancel()
        filesSharedExpiry = nil
        sendFiles(shared.sources)
    }

    /// The share question's Cancel.
    func cancelShared() {
        guard let shared = filesShared else { return }
        filesShared = nil
        filesSharedExpiry?.cancel()
        filesSharedExpiry = nil
        dropShared(shared)
    }

    private func dropShared(_ shared: FilesShared) {
        for s in shared.sources where s.ownCopy { DeviceFiles.deleteOwnCopy(s.url) }
    }
}
