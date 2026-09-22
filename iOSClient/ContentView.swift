import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var client = StreamClient()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if client.connected {
                StreamScreen(client: client)
            } else {
                ConnectScreen(client: client)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { client.startBrowsing() }
    }
}

/// Before a Mac is picked: the Bonjour results as drawer-style rows.
struct ConnectScreen: View {
    @ObservedObject var client: StreamClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect to a Mac")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)

            Text(client.status)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(client.hosts, id: \.self) { host in
                DrawerRow(height: 50, highlighted: false, title: name(of: host), trailing: nil,
                          action: { client.connect(to: host) }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.iconFallback)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
            }
        }
        .frame(width: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func name(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }
}
