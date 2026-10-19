import Foundation
import Combine
struct Window: Equatable { let id: UInt32; let title: String }
struct List { let windows: [Window]; let active: UInt32; var runningApps: [String]? = nil }
final class Client: ObservableObject {
    @Published var runningApps: [String]? = nil
    @Published var windows: [Window] = []
    @Published var active: UInt32 = 0
    @Published var thumbnails: [UInt32: Int] = [:]
    func apply(_ list: List) {
        /* RECEIVER */
    }
}
func expect(_ condition: Bool, _ label: String) { if !condition { fatalError(label) } }
let a = Window(id: 1, title: "A"), b = Window(id: 2, title: "B")
let client = Client()
client.apply(List(windows: [a,b], active: 1)); client.thumbnails = [1: 100, 2: 200]
var windowWrites = 0, activeWrites = 0, thumbnailWrites = 0
let w = client.$windows.dropFirst().sink { _ in windowWrites += 1 }
let aToken = client.$active.dropFirst().sink { _ in activeWrites += 1 }
let t = client.$thumbnails.dropFirst().sink { _ in thumbnailWrites += 1 }
for _ in 0..<20 { client.apply(List(windows: [a,b], active: 1)) }
expect(windowWrites == 0 && activeWrites == 0 && thumbnailWrites == 0, "unchanged acknowledgements publish nothing")
client.apply(List(windows: [a,b], active: 2))
expect(activeWrites == 1 && windowWrites == 0 && thumbnailWrites == 0, "selection only publishes active source")
let resized = Window(id: 1, title: "Changed")
client.apply(List(windows: [resized,b], active: 2))
expect(windowWrites == 1 && thumbnailWrites == 0, "live metadata changes remain visible without clearing images")
client.apply(List(windows: [b,resized], active: 2))
expect(windowWrites == 2, "real order changes remain visible")
client.apply(List(windows: [b], active: 2))
expect(windowWrites == 3 && thumbnailWrites == 1 && client.thumbnails == [2: 200], "closed window removes only its image")
client.apply(List(windows: [], active: 0))
expect(windowWrites == 4 && activeWrites == 2 && thumbnailWrites == 2 && client.thumbnails.isEmpty, "disconnect/empty list clears live state")
var appWrites = 0
let appsToken = client.$runningApps.dropFirst().sink { _ in appWrites += 1 }
let listed = List(windows: [], active: 0, runningApps: ["regular", "minimized", "windowless"])
client.apply(listed)
for _ in 0..<20 { client.apply(listed) }
expect(appWrites == 1, "unchanged running-app acknowledgements publish once")
client.apply(List(windows: [], active: 0, runningApps: []))
expect(appWrites == 2 && client.runningApps == [], "authoritative empty inventory clears running apps")
client.apply(List(windows: [], active: 0))
expect(appWrites == 3 && client.runningApps == nil, "legacy session cannot retain another host inventory")
print("client-catalog: unchanged, selection, metadata, ordering, removal and clearing checks passed")
