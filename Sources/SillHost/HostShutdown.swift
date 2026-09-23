import Foundation
import Darwin

/// Orderly exit for `--virtual-display` mode: a Ctrl-C, `kill` or hangup must put the streamed
/// window back on its real display before the process dies. Without this the window server dumps
/// the window somewhere on a real display when the virtual one vanishes with the process, which
/// is "not lost" but not where the user left it either.
///
/// Installed only under the flag; the default host path exits on a signal exactly as it did.
///
/// Threading: the signal sources fire on the main queue, i.e. on the main thread at a point where
/// no main-actor code is mid-statement (an in-flight `select` is parked at an await), so the
/// coordinator's state is consistent and `shutdownForExit()` can run synchronously. A watchdog on
/// a global queue exits anyway if an Accessibility call into a wedged app never returns.
enum HostShutdown {
    /// Kept for the life of the process: a released DispatchSourceSignal stops delivering.
    static var sources: [DispatchSourceSignal] = []
    static var began = false

    /// `coordinator` is read at signal time, not now: the coordinator is created asynchronously
    /// after `install` runs.
    static func install(coordinator: @escaping () -> StreamCoordinator?) {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            // The default disposition would kill the process before the source fires.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { begin(code: 128 + sig, coordinator: coordinator) }
            source.resume()
            sources.append(source)
        }
        // Covers `exit(1)` from a failed listener or startup: nothing is staged at either in
        // practice, but the snapshot restore costs nothing and needs no main-actor state.
        atexit { VirtualStage.emergencyRestore() }
    }

    static func begin(code: Int32, coordinator: () -> StreamCoordinator?) {
        if began { exit(code) }   // a second Ctrl-C leaves at once
        began = true
        print("Shutting down: putting the window back and removing the virtual display.")
        // Off the main queue, so a stuck AX call cannot hold the exit hostage; atexit then
        // restores from the snapshot instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            print("Shutdown timed out; exiting anyway.")
            exit(code)
        }
        MainActor.assumeIsolated { coordinator()?.shutdownForExit() }
        exit(code)
    }
}
