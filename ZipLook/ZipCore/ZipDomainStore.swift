import Foundation

/// Shared registry mapping a File Provider domain to a security-scoped bookmark of the
/// user's source zip. Stored as **plain files** in the dedicated `.share` App Group
/// container (`bookmarks/<domainID>.bookmark` + `.name`), read directly to bypass
/// cfprefsd caching — the File Provider extension doesn't reliably see the app's
/// UserDefaults writes.
enum ZipDomainStore {
    /// Dedicated sharing group — separate from the FP-managed document group.
    static let appGroupID = "group.org.deadkittens.ziplook.share"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func dir() -> URL? {
        guard let base = containerURL()?.appendingPathComponent("bookmarks", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func set(bookmark: Data, displayName: String, forDomainID id: String) {
        guard let dir = dir() else { NSLog("ZLFP store.set: no container"); return }
        do {
            try bookmark.write(to: dir.appendingPathComponent("\(id).bookmark"), options: .atomic)
            try Data(displayName.utf8).write(to: dir.appendingPathComponent("\(id).name"), options: .atomic)
            NSLog("ZLFP store.set: wrote \(bookmark.count)B for \(id) to \(dir.path)")
        } catch {
            NSLog("ZLFP store.set error: \(error)")
        }
    }

    static func bookmark(forDomainID id: String) -> Data? {
        guard let dir = dir() else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent("\(id).bookmark"))
    }

    static func displayName(forDomainID id: String) -> String? {
        guard let dir = dir() else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(id).name")) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func allDomainIDs() -> [String] {
        guard let dir = dir(),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".bookmark") }.map { String($0.dropLast(".bookmark".count)) }
    }

    static func remove(domainID id: String) {
        guard let dir = dir() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).bookmark"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).name"))
    }
}
