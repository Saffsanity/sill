import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var client = StreamClient()

    var body: some View {
        ZStack(alignment: .topLeading) {
            StreamView(client: client)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                if client.connected {
                    Text("\(client.fps) fps · frame age ≈ \(client.frameAgeMs) ms")
                        .font(.caption.monospacedDigit())
                    Button("Disconnect") { client.disconnect() }
                        .font(.caption)
                } else {
                    Text(client.status).font(.caption)
                    ForEach(client.hosts, id: \.self) { host in
                        Button(name(of: host)) { client.connect(to: host) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
        .onAppear { client.startBrowsing() }
    }

    private func name(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }
}
