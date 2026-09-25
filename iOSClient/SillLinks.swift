import Foundation

/// Sill's addresses on the web, written once. The site is not final (sill.saffer.me, on Noah's
/// saffer.me, is still to be confirmed): change `site` and the download, support and privacy
/// links and the connect screen's "Get it at …" all follow.
enum SillLinks {
    /// The site. Its host is what the connect screen prints.
    static let site = URL(string: "https://sill.saffer.me")!
    /// Where the free Sill for Mac is downloaded (the connect screen's footer).
    static let download = site.appending(path: "download")
    /// Help, and how to reach the developer, which guideline 1.5 wants inside the app as well as
    /// behind App Store Connect's Support URL (the connect screen's footer).
    static let support = site.appending(path: "support")
    /// The privacy policy, which guideline 5.1.1(i) wants linked inside the app as well as in
    /// App Store Connect (the connect screen's footer).
    static let privacy = site.appending(path: "privacy")
    /// The site as a person types it: its host alone, "sill.saffer.me".
    static let siteName = site.host() ?? site.absoluteString
}
