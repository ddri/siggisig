import Foundation

struct Route: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let bundleID: String?
    let pid: pid_t
    var slot: Int
    var volume: Float = 0.0  // dB, 0.0 = unity gain
    var pan: Float = 0.0     // -1.0 (left) to +1.0 (right), 0.0 = center

    var channelPair: String { Self.channelPairLabel(for: slot) }

    static func channelPairLabel(for slot: Int) -> String {
        let first = slot * 2 + 1
        let second = slot * 2 + 2
        return "Ch \(first)-\(second)"
    }
}

struct RouterState {
    private(set) var routes: [Route] = []
    let maxSlots = 8

    var availableSlots: Int { maxSlots - routes.count }

    var statusText: String {
        if routes.isEmpty {
            return "No apps routed"
        }
        return "Routing \(routes.count) app\(routes.count == 1 ? "" : "s") to BlackHole"
    }

    mutating func addRoute(appName: String, bundleID: String?, pid: pid_t, slot: Int) {
        let route = Route(appName: appName, bundleID: bundleID, pid: pid, slot: slot)
        routes.append(route)
    }

    mutating func removeRoute(pid: pid_t) {
        routes.removeAll { $0.pid == pid }
    }

    func slotFor(pid: pid_t) -> Int? {
        routes.first { $0.pid == pid }?.slot
    }

    mutating func setVolume(pid: pid_t, volume: Float) {
        guard let index = routes.firstIndex(where: { $0.pid == pid }) else { return }
        routes[index].volume = volume
    }

    mutating func setPan(pid: pid_t, pan: Float) {
        guard let index = routes.firstIndex(where: { $0.pid == pid }) else { return }
        routes[index].pan = min(max(pan, -1.0), 1.0)
    }

    mutating func reassignSlot(pid: pid_t, to newSlot: Int) {
        guard let index = routes.firstIndex(where: { $0.pid == pid }) else { return }
        routes[index].slot = newSlot
    }
}
