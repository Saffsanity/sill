import Foundation
import StreamProtocol

// The iOS app's DEBUG harness (ContentView's InputScript and SettingsScript, MockCatalog's mock Mac
// menus) drives the iPad's own views and has no Mac counterpart. StreamClient's DEBUG paths call into
// it; on the Mac these stand-ins keep them inert, so a Debug build behaves as a Release one does.

#if DEBUG
enum InputScript {
    /// The Mac client never runs the input script: every session is refused.
    static func refusal(endpoint: Any?, hostVersion: String?) -> String? {
        "the input script runs only in the iPhone and iPad app"
    }
    static func sessionListed(_ client: StreamClient) {}
}

enum SettingsScript {
    static func sessionListed(_ client: StreamClient) {}
}

enum MockCatalog {
    /// The harness's mock Mac menus. The Mac client has no harness, so none is ever made.
    struct MacMenus {
        let topLevel: MacMenu
        let fetchDelay: TimeInterval? = nil
        func answer(_ request: FetchMenu) -> MacMenu { topLevel }
        func answer(_ request: PressMenuItem) -> MacMenu { topLevel }
    }
}
#endif
