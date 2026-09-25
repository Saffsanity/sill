import Foundation

/// Where Sill sends people outside the app.
enum SillLinks {
    /// Sill's App Store page, https://apps.apple.com/app/id‹Apple ID›. The Apple ID is the App Store
    /// Connect record's, known once the record exists: the release checklist fills it in before the
    /// first upload. While the placeholder stays, no link shows (the update notice's own words say
    /// what to do).
    static let appStoreText = "APP_STORE_URL_PLACEHOLDER"

    /// An https URL from `appStoreText`, else nil. DEBUG: `-SillAppStoreURL <url>` replaces it.
    static var appStore: URL? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "SillAppStoreURL"), let url = https(override) { return url }
        #endif
        return https(appStoreText)
    }

    private static func https(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
