import Foundation

/// Small in-memory cache of palettes by track key, evicting the oldest entry first.
/// Replaying a track then skips the artwork fetch. Not thread-safe: callers lock.
struct PaletteCache {
    private(set) var capacity: Int
    private var entries: [String: Palette] = [:]
    private var order: [String] = []

    init(capacity: Int = 50) { self.capacity = max(1, capacity) }

    var count: Int { entries.count }

    func palette(for key: String) -> Palette? { entries[key] }

    mutating func store(_ palette: Palette, for key: String) {
        if entries[key] == nil { order.append(key) }
        entries[key] = palette
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }
}
