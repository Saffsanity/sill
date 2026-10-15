/// The shared StreamClient tells the iPad's menu bar when the Mac's top level changes (the iOS app's
/// MacMenuHub); here the menu bar (MainMenu) rebuilds from it.
final class MacMenuHub {
    static let shared = MacMenuHub()
    var onChange: ((StreamClient) -> Void)?
    func menusChanged(_ client: StreamClient) {
        onChange?(client)
        #if DEBUG
        MacMenus.testIfAsked(client)   // -SillMenuTest 1|press
        #endif
    }
}
