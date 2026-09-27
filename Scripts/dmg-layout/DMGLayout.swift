import Foundation

/// The window a disk image opens in, as .DS_Store records: icon view with no toolbar, sidebar,
/// path bar or status bar, a background picture the size of its content, and each item's icon at a
/// point of that picture.
struct DMGLayout: Equatable {
    struct Item: Equatable {
        var name: String
        var x: Int
        var y: Int
    }

    /// The window's content in points: the background picture's size at 1x.
    var width: Int
    var height: Int
    /// The window's top-left corner on the screen.
    var left: Int
    var top: Int
    var iconSize: Int
    var textSize: Int
    /// The picture's path on the volume, such as ".background/background.tiff".
    var background: String
    /// The view's colour behind the picture, for where the window is larger than it: the picture's
    /// edge colour. (Finder may show its own fill there instead: white in Light Mode, so a picture
    /// white to its edges, as Sill's is, looks the same either way.)
    var backgroundColor: (red: Int, green: Int, blue: Int)
    /// Where each icon's centre sits, in points from the content's top-left corner.
    var items: [Item]
    /// Hidden items (.background, .VolumeIcon.icns), put below the window, out of sight for anyone
    /// who shows hidden files in Finder; otherwise Finder would place them among the others.
    var hidden: [String]

    /// Finder's WindowBounds is the whole window, its title bar included, and a window with no
    /// toolbar has only that bar above its content: 32 points on macOS 27 (AppKit's
    /// NSWindow.frameRect(forContentRect:styleMask:) for a titled window, on a Mac whose Finder is
    /// built with the same SDK), 28 on macOS 11 to 15 (not measured here). The window is sized for
    /// the taller bar: on macOS 27 its content is exactly the picture, and under a 28-point bar it
    /// is 4 points taller, a strip below the picture that shows white, as every edge of the picture
    /// is (make-dmg.sh's backgroundColor, and Finder's own fill in Light Mode). Sized for 28, the
    /// window would hide the picture's bottom 4 points on macOS 27; sized to the picture alone, as
    /// some images are (a Finder-made one of 2023: 512 x 400 for a 512 x 400 picture), 32.
    static let titleBar = 32

    static func == (a: DMGLayout, b: DMGLayout) -> Bool {
        a.width == b.width && a.height == b.height && a.left == b.left && a.top == b.top
            && a.iconSize == b.iconSize && a.textSize == b.textSize && a.background == b.background
            && a.backgroundColor == b.backgroundColor && a.items == b.items && a.hidden == b.hidden
    }

    var windowBounds: String { "{{\(left), \(top)}, {\(width), \(height + Self.titleBar)}}" }

    /// Browser window settings: the window's place and size, and no bars.
    var browserWindowSettings: [String: Any] {
        [
            "ContainerShowSidebar": false,
            "PreviewPaneVisibility": false,
            "ShowPathbar": false,
            "ShowSidebar": false,
            "ShowStatusBar": false,
            "ShowTabView": false,
            "ShowToolbar": false,
            "SidebarWidth": 0,
            "WindowBounds": windowBounds,
        ]
    }

    /// Icon view options: the picture (type 2) through its alias, icon and text size, no grid
    /// arrangement, names below the icons.
    func iconViewSettings(backgroundAlias: Data) -> [String: Any] {
        [
            "arrangeBy": "none",
            "backgroundColorBlue": Double(backgroundColor.blue) / 255,
            "backgroundColorGreen": Double(backgroundColor.green) / 255,
            "backgroundColorRed": Double(backgroundColor.red) / 255,
            "backgroundImageAlias": backgroundAlias,
            "backgroundType": 2,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "iconSize": Double(iconSize),
            "labelOnBottom": true,
            "showIconPreview": true,
            "showItemInfo": false,
            "textSize": Double(textSize),
            "viewOptionsVersion": 1,
        ]
    }

    /// An icon's place: its centre, then the four bytes ff ff ff ff and ff ff 00 00 Finder writes.
    static func location(x: Int, y: Int) -> Data {
        var data = Data()
        data.appendWord(UInt32(x))
        data.appendWord(UInt32(y))
        data.append(contentsOf: [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0])
        return data
    }

    /// Where the hidden items go: a row below the window's content.
    func hiddenLocation(_ index: Int) -> (x: Int, y: Int) {
        (x: iconSize + index * (iconSize + 60), y: height + iconSize * 2)
    }

    /// The .DS_Store records for this window, the background named by `backgroundAlias`.
    func records(backgroundAlias: Data) throws -> [DSRecord] {
        func plist(_ value: [String: Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        }
        var records = [
            DSRecord(name: ".", code: "bwsp", value: .blob(try plist(browserWindowSettings))),
            DSRecord(name: ".", code: "icvp", value: .blob(try plist(iconViewSettings(backgroundAlias: backgroundAlias)))),
            DSRecord(name: ".", code: "vSrn", value: .long(1)),
            DSRecord(name: ".", code: "vstl", value: .type("icnv")),   // icon view, whatever the Mac's default view
        ]
        for item in items {
            records.append(DSRecord(name: item.name, code: "Iloc", value: .blob(Self.location(x: item.x, y: item.y))))
        }
        for (index, name) in hidden.enumerated() {
            let place = hiddenLocation(index)
            records.append(DSRecord(name: name, code: "Iloc", value: .blob(Self.location(x: place.x, y: place.y))))
        }
        return records.sorted(by: DSStore.precedes)
    }

    /// The whole .DS_Store for the volume mounted at `volume`, whose background file must be there.
    func dsStore(onVolumeAt volume: String, timeZone: TimeZone = .current) throws -> Data {
        let alias = try FinderAlias.forFile(background, onVolumeAt: volume)
        return try DSStore.encode(try records(backgroundAlias: try alias.encoded(timeZone: timeZone)))
    }
}

/// The volume's own icon: .VolumeIcon.icns at its root, shown only while the root folder's Finder
/// info has the custom-icon flag (kHasCustomIcon, 0x0400, the 2-byte Finder flags at offset 8 of
/// the 32-byte com.apple.FinderInfo). SetFile -a C sets it; SetFile ships with Xcode's command line
/// tools only, so this sets the attribute itself, keeping the other 30 bytes.
enum VolumeIcon {
    static let attribute = "com.apple.FinderInfo"
    static let hasCustomIcon: UInt16 = 0x0400

    static func finderInfo(_ path: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 32)
        let read = getxattr(path, attribute, &bytes, 32, 0, XATTR_NOFOLLOW)
        return read == 32 ? bytes : [UInt8](repeating: 0, count: 32)
    }

    static func flags(_ path: String) -> UInt16 {
        let info = finderInfo(path)
        return UInt16(info[8]) << 8 | UInt16(info[9])
    }

    static func setCustomIcon(_ path: String) throws {
        var info = finderInfo(path)
        let flags = (UInt16(info[8]) << 8 | UInt16(info[9])) | hasCustomIcon
        info[8] = UInt8(flags >> 8)
        info[9] = UInt8(flags & 0xff)
        guard setxattr(path, attribute, info, 32, 0, XATTR_NOFOLLOW) == 0 else {
            throw DSStoreError("can't set \(path)'s custom-icon flag: \(String(cString: strerror(errno)))")
        }
    }
}
