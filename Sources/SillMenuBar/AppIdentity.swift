import Foundation
import Security

/// Whether this process is Sill.app itself or the bare SillMenuBar binary that `swift build` makes,
/// which alone honours the TEST ONLY hooks that bear on who gets in or on what pairing needs (the
/// test directory's trust list, `-requirePairing`, the `-Sill…After` hooks, the doors' `SILL_TEST_*`
/// variables: docs/home-pairing-plan.md §4.3). Sill.app runs with Sill's Screen Recording and
/// Accessibility grants, and any process of this user can start it, or a copy of it, with an
/// environment and arguments of its own.
///
/// Until 2026-10-29 Sill.app was "a main bundle whose folder ends in .app" (the security scan of
/// 2026-10-18, finding 1). A copy renamed Sill.bin read as the bare binary, and so did Sill.app's own
/// executable started through a symlink or a hard link (Foundation then finds no bundle around it),
/// while each would keep the grants (the scan's premise, not tried here): macOS keys them to the code's
/// bundle ID and designated requirement, never to its path. So it is decided by what the code is. `AppModel.bundled` is `isSillApp` of
/// the facts read at launch (`Facts.current`). Pure but for that reader, which
/// Tests/checks/test-host runs on its own code, signed and copied in each way the rule names.
enum AppIdentity {
    /// Sill.app's bundle identifier (Packaging/Info.plist), which codesign also makes its signing
    /// identifier (Scripts/make-app.sh), and so the first clause of its designated requirement.
    static let sill = "me.saffer.sill.mac"

    /// How the running code is signed.
    enum Signature: Equatable, Sendable {
        /// No signature at all: an x86_64 build (the linker signs only arm64 code).
        case unsigned
        /// No certificate: the linker's own signature (`swift build`), or `codesign -s -`.
        case adHoc
        /// Signed with a certificate: Apple Development, Developer ID, or any other.
        case certificate
        /// The signature could not be read.
        case unreadable
    }

    /// What the process knows about itself at launch.
    struct Facts: Equatable, Sendable {
        /// The running code's signing identifier, as the kernel holds it (SecTaskCopySigningIdentifier;
        /// the signature on disk only if that has none): `me.saffer.sill.mac` for Sill.app, the
        /// linker's name for the file (`SillMenuBar`) for the bare binary, nil for unsigned code.
        var signingIdentifier: String?
        var signature: Signature
        /// The main bundle's CFBundleIdentifier (Bundle.main). Foundation reads Contents/Info.plist
        /// whatever the folder is called; nil for the bare binary, which has no Info.plist, and for an
        /// executable started outside its bundle (a link to it).
        var bundleIdentifier: String?
        /// The main bundle's folder (Bundle.main.bundlePath): the bare binary's is its build folder.
        var bundlePath: String
    }

    /// Sill.app's own code, wherever and however it runs (true), or the bare binary as `swift build`
    /// makes it (false). Any one of these makes it Sill.app:
    /// - Signed as Sill (`me.saffer.sill.mac`, in any case). A TCC grant to Sill is kept with Sill's
    ///   designated requirement, which begins `identifier "me.saffer.sill.mac"`, so every copy of the
    ///   code that can hold Sill's grants carries it: renamed, moved, flat, linked. The kernel's copy
    ///   of it, which no folder, file name or later change on disk alters; signing the code again
    ///   under another identifier gives the grants up.
    /// - Signed with a certificate, whatever its identifier: a build whose grants outlast a rebuild.
    ///   The bare binary has only the linker's ad hoc signature (none on Intel).
    /// - A signature that could not be read: not known to be the bare binary.
    /// - A bundle that says it is Sill (its CFBundleIdentifier, in any case).
    /// - A `.app` folder, in any case (the rule before 2026-10-29, kept so nothing that refused the
    ///   hooks takes them now).
    static func isSillApp(_ f: Facts) -> Bool {
        if let id = f.signingIdentifier, id.lowercased() == sill { return true }
        switch f.signature {
        case .certificate, .unreadable: return true
        case .adHoc, .unsigned: break
        }
        if let id = f.bundleIdentifier, id.lowercased() == sill { return true }
        return (f.bundlePath as NSString).pathExtension.lowercased() == "app"
    }

    /// One line for the log when Sill.app's code runs from a folder that is not a `.app` (a renamed
    /// copy, a link to its executable): what made it Sill.app. Nil otherwise: Sill.app where it
    /// belongs, and the bare binary, print nothing new.
    static func note(_ f: Facts) -> String? {
        guard isSillApp(f), (f.bundlePath as NSString).pathExtension.lowercased() != "app" else { return nil }
        let why: String
        if let id = f.signingIdentifier, id.lowercased() == sill {
            why = "signed \(id)"
        } else if f.signature == .certificate {
            why = "signed with a certificate"
        } else if f.signature == .unreadable {
            why = "its signature could not be read"
        } else {
            why = "its bundle says \(f.bundleIdentifier ?? sill)"
        }
        return "Running from \(f.bundlePath), which is not a .app, as Sill.app itself (\(why)): it takes no test hook."
    }
}

extension AppIdentity.Facts {
    /// This process's facts. Read once, at launch (`AppModel.launchIdentity`).
    static func current() -> AppIdentity.Facts {
        var kernel: String?
        if let task = SecTaskCreateFromSelf(nil) { kernel = SecTaskCopySigningIdentifier(task, nil) as String? }
        // This process's code not found (never seen: the check reads itself however it starts): as a
        // signature that could not be read.
        var signed = AppIdentity.signature(read: nil)
        var code: SecCode?
        var onDisk: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code,
           SecCodeCopyStaticCode(code, [], &onDisk) == errSecSuccess, let onDisk {
            signed = AppIdentity.signature(of: onDisk)
        }
        return AppIdentity.Facts(signingIdentifier: kernel ?? signed.identifier, signature: signed.signature,
                                 bundleIdentifier: Bundle.main.bundleIdentifier, bundlePath: Bundle.main.bundlePath)
    }
}

extension AppIdentity {
    /// A code signature as `isSillApp` reads it: its signing information (`signature(read:)`).
    static func signature(of code: SecStaticCode) -> (identifier: String?, signature: Signature) {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return signature(read: status == errSecSuccess ? info as? [String: Any] : nil)
    }

    /// What a signature's information (SecCodeCopySigningInformation's, kSecCSSigningInformation)
    /// says, pure: none at all (it could not be read) is `.unreadable`; no identifier is no
    /// signature, `.unsigned`; a certificate (any chain at all), `.certificate`; the ad hoc flag,
    /// `.adHoc`; an identifier with neither, `.unreadable`. Only the bare binary's kinds (ad hoc, or
    /// none on Intel) can make a test host, so anything else fails closed. Measured on 2026-10-29:
    /// Security answers without an error for a copy whose superblob or identifier is damaged (no
    /// identifier: `.unsigned`) and for one deleted once opened (read as before), so the two
    /// `.unreadable` answers are this function's promise for failures no file here showed
    /// (Tests/checks/test-host checks them here, and the file reader on real files).
    static func signature(read d: [String: Any]?) -> (identifier: String?, signature: Signature) {
        guard let d else { return (nil, .unreadable) }
        guard let id = d[kSecCodeInfoIdentifier as String] as? String else { return (nil, .unsigned) }
        if let chain = d[kSecCodeInfoCertificates as String] as? [Any], !chain.isEmpty { return (id, .certificate) }
        let flags = (d[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return (id, .adHoc) }
        return (id, .unreadable)
    }
}
