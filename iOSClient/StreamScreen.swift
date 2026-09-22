import SwiftUI
import StreamProtocol

// MARK: - Palette

extension Color {
    /// 0xRRGGBB, the way the design boards write colours.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let bar = Color(hex: 0x16181C)          // top bar and drawer background
    static let control = Color(hex: 0x23262C)      // bar buttons, search field, selected row
    static let controlOpen = Color(hex: 0x2C3550)  // a bar button whose thing is showing
    static let accent = Color(hex: 0x9BB7FF)
    static let text = Color(hex: 0xEEF0F3)
    static let barLabel = Color(hex: 0xC4C9D1)     // the 11pt labels under the bar icons
    static let muted = Color(hex: 0xA4ABB5)        // section headers, window counts, placeholder
    static let panel = Color(hex: 0x1F2126)        // the stream panel behind the video
    static let thumbBody = Color(hex: 0x26282D)    // thumbnail placeholder
    static let thumbTitleBar = Color(hex: 0x34373D)
    static let iconFallback = Color(hex: 0x3A3D44) // two-letter app badge
}

// MARK: - Screen

struct StreamScreen: View {
    @ObservedObject var client: StreamClient
    @State private var drawerOpen = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(client: client, drawerOpen: $drawerOpen)
            contentArea
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // A fresh connection streams nothing: the Mac no longer picks a window, the iPad does.
            if client.active == .none { drawerOpen = true }
        }
        .onChange(of: client.active) { _, source in
            withAnimation(.easeOut(duration: 0.18)) { drawerOpen = (source == .none) }
        }
    }

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var contentArea: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            StreamView(client: client)
                .background(Palette.panel)
                .clipShape(streamShape)
                .overlay(streamShape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                .padding(8)

            if drawerOpen {
                Color.black.opacity(0.58)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
                    .accessibilityHidden(true)
                    .transition(.opacity)

                AppDrawer(client: client, drawerOpen: $drawerOpen)
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool

    var body: some View {
        HStack(spacing: 12) {
            BarButton(open: drawerOpen,
                      accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                      action: { withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() } }) {
                VStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(drawerOpen ? Palette.accent : Palette.text)
                    Text("Apps")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(drawerOpen ? Palette.accent : Palette.barLabel)
                }
            }

            WindowStrip(client: client)

            // Milestone 3 lives here: scaling the streamed window's text. Present, inert.
            BarButton(open: false, accessibilityLabel: "Text size, currently 1.0 times", action: {}) {
                VStack(spacing: 2) {
                    Text("Aa")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("1.0×")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.barLabel)
                }
            }

            BarButton(open: client.active == .desktop,
                      accessibilityLabel: "Show the full Mac desktop",
                      action: { client.select(.desktop) }) {
                VStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 22))
                        .foregroundStyle(client.active == .desktop ? Palette.accent : Palette.text)
                    Text("Desktop")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(client.active == .desktop ? Palette.accent : Palette.barLabel)
                }
            }
        }
        .frame(height: 86)
        .padding(.horizontal, 22)
        // The bar's colour runs to the screen edge; its contents stay inside the safe area.
        .background(Palette.bar.ignoresSafeArea(edges: .top))
    }
}

private struct BarButton<Content: View>: View {
    let open: Bool
    let accessibilityLabel: String
    let action: () -> Void
    let content: () -> Content

    init(open: Bool, accessibilityLabel: String, action: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.open = open
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 66, height: 66)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(open ? Palette.controlOpen : Palette.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Window thumbnails

private struct WindowStrip: View {
    @ObservedObject var client: StreamClient

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(client.windows) { window in
                    WindowThumbnail(window: window,
                                    image: client.thumbnails[window.id],
                                    icon: client.icons[window.bundleID],
                                    isActive: client.active == .window(window.id),
                                    action: { client.select(.window(window.id)) })
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                     .init(color: .black, location: 0.86),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }
}

private struct WindowThumbnail: View {
    let window: WindowInfo
    let image: UIImage?
    let icon: UIImage?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            preview
                .frame(width: 104, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .bottomLeading) { badge.offset(x: -6, y: 6) }
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                            .padding(-5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(window.appName) window: \(window.title)" + (isActive ? ", showing now" : ""))
    }

    @ViewBuilder private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            VStack(spacing: 0) {
                Palette.thumbTitleBar.frame(height: 9)
                Palette.thumbBody
            }
        }
    }

    private var badge: some View {
        AppIcon(image: icon, name: window.appName, size: 24, radius: 7, fontSize: 10)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.bar)
                    .frame(width: 28, height: 28)
            }
    }
}

/// An app icon, or its first two letters while the host has not sent one.
struct AppIcon: View {
    let image: UIImage?
    let name: String
    let size: CGFloat
    let radius: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Palette.iconFallback.overlay(
                    Text(String(name.prefix(2)))
                        .font(.system(size: fontSize, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - App drawer

private struct OpenApp: Identifiable {
    let bundleID: String
    let name: String
    let windows: [WindowInfo]
    var id: String { bundleID }
}

private struct AppDrawer: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @State private var search = ""

    var body: some View {
        VStack(spacing: 6) {
            searchField
            ScrollView {
                VStack(spacing: 6) {
                    if !openApps.isEmpty {
                        header("Open now")
                        ForEach(openApps) { app in
                            DrawerRow(height: 50,
                                      highlighted: app.bundleID == activeBundleID,
                                      title: app.name,
                                      trailing: app.windows.count == 1 ? "1 window" : "\(app.windows.count) windows",
                                      action: { show(app) }) {
                                AppIcon(image: client.icons[app.bundleID], name: app.name,
                                        size: 32, radius: 9, fontSize: 12)
                            }
                        }
                    }
                    if !closedApps.isEmpty {
                        header("All apps").padding(.top, 2)
                        ForEach(closedApps) { app in
                            DrawerRow(height: 46, highlighted: false, title: app.name, trailing: nil,
                                      action: { client.launch(bundleID: app.bundleID) }) {
                                AppIcon(image: client.icons[app.bundleID], name: app.name,
                                        size: 32, radius: 9, fontSize: 12)
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bar))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(Palette.muted)
            TextField("", text: $search,
                      prompt: Text("Search apps on \(client.macName)").foregroundColor(Palette.muted))
                .font(.system(size: 15))
                .foregroundStyle(Palette.text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel("Search apps on this Mac")
        }
        .frame(height: 48)
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }

    // MARK: Contents

    /// Running apps, grouped from the window list and kept in its front-to-back order.
    private var openApps: [OpenApp] {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [WindowInfo]] = [:]
        for window in client.windows {
            if grouped[window.bundleID] == nil {
                order.append(window.bundleID)
                names[window.bundleID] = window.appName
            }
            grouped[window.bundleID, default: []].append(window)
        }
        return order.map { OpenApp(bundleID: $0, name: names[$0] ?? $0, windows: grouped[$0] ?? []) }
            .filter { matches($0.name) }
    }

    private var closedApps: [AppInfo] {
        let running = Set(client.windows.map(\.bundleID))
        return client.apps
            .filter { !running.contains($0.bundleID) && matches($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var activeBundleID: String? {
        guard case .window(let id) = client.active else { return nil }
        return client.windows.first { $0.id == id }?.bundleID
    }

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || name.range(of: query, options: .caseInsensitive) != nil
    }

    /// First window of the app, or the next one if this app is already showing.
    private func show(_ app: OpenApp) {
        guard !app.windows.isEmpty else { return }
        var target = app.windows[0]
        if case .window(let id) = client.active,
           let index = app.windows.firstIndex(where: { $0.id == id }) {
            target = app.windows[(index + 1) % app.windows.count]
        }
        client.select(.window(target.id))
        withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false }
    }
}

/// One app row: icon, name, optional trailing count.
struct DrawerRow<Leading: View>: View {
    let height: CGFloat
    let highlighted: Bool
    let title: String
    let trailing: String?
    let action: () -> Void
    let leading: () -> Leading

    init(height: CGFloat, highlighted: Bool, title: String, trailing: String?,
         action: @escaping () -> Void, @ViewBuilder leading: @escaping () -> Leading) {
        self.height = height
        self.highlighted = highlighted
        self.title = title
        self.trailing = trailing
        self.action = action
        self.leading = leading
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(highlighted ? Palette.control : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
