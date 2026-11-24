/// Which windows a staged capture may show. An app filter keeps following new menus without a
/// restart; when another PID has the same bundle identifier, use explicit window IDs instead.
struct StageCaptureWindows: Equatable {
    struct Application: Equatable {
        let pid: Int32
        let bundleID: String
    }

    struct Window {
        let id: UInt32
        let owner: Application?
    }

    enum Filter: Equatable {
        case application(Int32)
        case windows(Set<UInt32>)
    }

    let selectedID: UInt32
    let filter: Filter

    init(selected: Window, applications: [Application], windows: [Window]) {
        selectedID = selected.id
        guard let owner = selected.owner else {
            filter = .windows([selected.id])
            return
        }
        let owners = applications + windows.compactMap(\.owner)
        let collision = !owner.bundleID.isEmpty && owners.contains {
            $0.pid != owner.pid && $0.bundleID.lowercased() == owner.bundleID.lowercased()
        }
        if collision {
            filter = .windows(Set(windows.filter { $0.owner?.pid == owner.pid }.map(\.id)).union([selected.id]))
        } else {
            filter = .application(owner.pid)
        }
    }
}
