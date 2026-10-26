import SwiftUI
import StreamProtocol

/// Every Mac this Mac paired with as a tile (its last picture, its name, how it is reached now),
/// then the Macs on this network not paired yet. A click opens the Mac in a window of its own, so
/// several Macs can stream at once; a Mac whose window is open is marked and brought forward.
///
/// The window's client only browses: it never connects. Each session window has a client of its
/// own, and the saved list stays one between them (StreamClient.storeSavedMacs).
struct DevicesWindow: View {
    @StateObject private var client = StreamClient()
    @ObservedObject private var sessions = SessionRegistry.shared
    @ObservedObject private var images = TileImages.shared
    @Environment(\.openWindow) private var openWindow

    @AppStorage("SillViewer.devicesLayout") private var layout = Layout.grid
    @AppStorage("SillViewer.devicesSort") private var sort = Sort.recent
    @State private var search = ""
    @State private var savedExpanded = true
    @State private var nearbyExpanded = true

    enum Layout: String { case grid, list }
    enum Sort: String { case recent, name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Saved Macs", expanded: $savedExpanded, tiles: savedTiles,
                        empty: "No Macs paired yet. Click a Mac below, or + to add one away from home.")
                if !nearbyTiles.isEmpty || savedTiles.isEmpty {
                    section("On This Network", expanded: $nearbyExpanded, tiles: nearbyTiles,
                            empty: client.status)
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .frame(minWidth: 560, minHeight: 360)
        .background(.background)
        .navigationTitle("Sill Viewer")
        .searchable(text: $search, placement: .toolbar, prompt: "Search")
        .toolbar { toolbar }
        .onAppear {
            client.startBrowsing()
            client.startRemote()
            #if DEBUG
            // `-SillOpenAddresses '127.0.0.1:P1,127.0.0.1:P2'`: a session window for each test host, as
            // a click on its tile would open it (the synthetic hosts are off Bonjour).
            for address in (UserDefaults.standard.string(forKey: "SillOpenAddresses") ?? "").split(separator: ",") {
                openWindow(id: "session", value: ViewerTarget(kind: .address, key: String(address), name: String(address)))
            }
            #endif
        }
        .onOpenURL { url in
            // A sill://pair link: confirmed, then paired, in a window of its own.
            openWindow(id: "session", value: ViewerTarget(kind: .add, key: "link:" + url.absoluteString, name: "Add a Mac"))
        }
    }

    // MARK: Tiles

    private func matches(_ tile: Tile) -> Bool {
        search.isEmpty || tile.name.localizedCaseInsensitiveContains(search) || (tile.detail?.localizedCaseInsensitiveContains(search) ?? false)
    }

    private var savedTiles: [Tile] {
        let tiles = client.savedMacs.map { saved -> Tile in
            let rows = client.macs.filter { $0.savedID == saved.macID }
            let row = rows.first { $0.route != .remote } ?? rows.first
            let name = client.displayName(saved.macID)
            return Tile(target: .saved(saved, name: name), name: name, row: row,
                        word: row?.word ?? (saved.revoked == true || saved.newKey == true ? "Not paired" : "Offline"),
                        detail: Self.lastConnected(saved), saved: saved)
        }
        .filter(matches)
        switch sort {
        case .name: return tiles.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent: return tiles.sorted { ($0.saved?.lastConnectedAt ?? $0.saved?.pairedAt ?? .distantPast) > ($1.saved?.lastConnectedAt ?? $1.saved?.pairedAt ?? .distantPast) }
        }
    }

    private var nearbyTiles: [Tile] {
        client.macs.filter { $0.savedID == nil }
            .map { Tile(target: .row($0), name: $0.name, row: $0, word: $0.word, detail: "Click to pair", saved: nil) }
            .filter(matches)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func lastConnected(_ saved: SavedMac) -> String {
        guard let at = saved.lastConnectedAt else { return "Paired \(saved.pairedAt.formatted(.relative(presentation: .named)))" }
        return "Last connected \(at.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder
    private func section(_ title: String, expanded: Binding<Bool>, tiles: [Tile], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(expanded.wrappedValue ? 0 : -90))
                        .foregroundStyle(.secondary)
                    Text(title).font(.title2.weight(.semibold))
                    if !tiles.isEmpty {
                        Text("\(tiles.count)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                if tiles.isEmpty {
                    Text(search.isEmpty ? empty : "Nothing matches “\(search)”.")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 22)
                } else if layout == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 16)], alignment: .leading, spacing: 16) {
                        ForEach(tiles) { tile in
                            DeviceTile(tile: tile, image: images.image(tile.target.tileKey), state: sessions.states[tile.target.tileKey])
                                .onTapGesture { open(tile) }
                                .contextMenu { menu(tile) }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                            if index > 0 { Divider().padding(.leading, 76) }
                            DeviceRow(tile: tile, image: images.image(tile.target.tileKey), state: sessions.states[tile.target.tileKey])
                                .onTapGesture { open(tile) }
                                .contextMenu { menu(tile) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.4)))
                }
            }
        }
    }

    private func open(_ tile: Tile) {
        openWindow(id: "session", value: tile.target)
    }

    @ViewBuilder private func menu(_ tile: Tile) -> some View {
        Button(sessions.states[tile.target.tileKey] == nil ? "Connect" : "Show Window") { open(tile) }
        if let saved = tile.saved {
            Divider()
            Button("Forget \(tile.name)…", role: .destructive) { client.forget(saved.macID) }
        }
    }

    // MARK: Toolbar and footer

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { openWindow(id: "session", value: ViewerTarget.add()) } label: {
                Label("Add a Mac", systemImage: "plus")
            }
            .help("Pair with a Mac away from home, by its address and code")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("Layout", selection: $layout) {
                Label("Tiles", systemImage: "square.grid.2x2").tag(Layout.grid)
                Label("List", systemImage: "list.bullet").tag(Layout.list)
            }
            .pickerStyle(.segmented)
            .help("Show Macs as tiles or as a list")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $sort) {
                    Text("Last Connected").tag(Sort.recent)
                    Text("Name").tag(Sort.name)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort the Macs")
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("Each Mac needs the free Sill app.").foregroundStyle(.secondary)
            Link("Get it at \(SillLinks.siteName)", destination: SillLinks.download)
            Text("·").foregroundStyle(.tertiary)
            Link("Support", destination: SillLinks.support)
            Text("·").foregroundStyle(.tertiary)
            Link("Privacy Policy", destination: SillLinks.privacy)
        }
        .font(.footnote)
        .padding(.top, 6)
    }
}

/// One Mac on the Devices window.
struct Tile: Identifiable {
    let target: ViewerTarget
    let name: String
    let row: FoundMac?
    /// How it is reached now ("Wi‑Fi", "Wired", "Remote", "Not paired"), "Offline" when not at all.
    let word: String?
    let detail: String?
    let saved: SavedMac?
    var id: String { target.tileKey }
}

/// A tile: the Mac's last picture (else a gradient of its own colour), a chip saying how it is
/// reached, its name and when it was last used. 16:10, about two thirds of the reference's size.
private struct DeviceTile: View {
    let tile: Tile
    let image: NSImage?
    let state: SessionRegistry.State?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TileBackground(name: tile.name, image: image, dimmed: tile.word == "Offline")
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    TileChip(word: state == .connected ? "Connected" : state == .connecting ? "Connecting…" : (tile.word ?? "Nearby"),
                             live: state != nil || (tile.row != nil && tile.word != "Not paired"))
                    Spacer()
                }
                Spacer()
                Text(tile.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                if let detail = tile.detail {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .connected ? Color.green : Color.primary.opacity(hovering ? 0.25 : 0.08),
                              lineWidth: state == .connected ? 2.5 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.22 : 0.12), radius: hovering ? 10 : 5, y: hovering ? 5 : 2)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help(tile.row == nil && tile.saved != nil ? "\(tile.name) isn’t on this network; Sill tries to reach it from afar" : "Open \(tile.name)")
    }
}

/// The list's row: a small picture, the name, the detail and the chip.
private struct DeviceRow: View {
    let tile: Tile
    let image: NSImage?
    let state: SessionRegistry.State?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            TileBackground(name: tile.name, image: image, dimmed: tile.word == "Offline")
                .frame(width: 52, height: 33)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.name).lineLimit(1)
                if let detail = tile.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Text(state == .connected ? "Connected" : state == .connecting ? "Connecting…" : (tile.word ?? ""))
                .font(.callout)
                .foregroundStyle(state == .connected ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .onHover { hovering = $0 }
    }
}

/// The Mac's last picture, or a gradient whose hues come from its name, so each Mac keeps its colour.
private struct TileBackground: View {
    let name: String
    let image: NSImage?
    let dimmed: Bool

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                let hue = Self.hue(name)
                ZStack {
                    LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.95),
                                            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle()
                        .fill(Color(hue: (hue + 0.92).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.85).opacity(0.55))
                        .blur(radius: 40)
                        .offset(x: 70, y: -40)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                        .offset(y: -10)
                }
            }
        }
        .saturation(dimmed ? 0.2 : 1)
        .opacity(dimmed ? 0.75 : 1)
        .clipped()
    }

    /// A stable hue per name (String.hashValue changes every launch).
    static func hue(_ name: String) -> Double {
        let sum = name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return Double(sum % 360) / 360
    }
}

private struct TileChip: View {
    let word: String
    let live: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(live ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(word).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
