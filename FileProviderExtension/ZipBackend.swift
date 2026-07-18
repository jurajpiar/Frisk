import Foundation

/// Serves a real zip. Resolves the domain's security-scoped bookmark to the user's
/// *original* zip (e.g. in Downloads), lists its central directory via ZipCore, and
/// extracts single entries on demand for materialisation.
final class ZipBackend: ProviderBackend {
    private let displayName: String
    private let zipURL: URL
    private let didStartAccess: Bool
    private let reader: ZipArchiveReader
    private let entries: [ZipEntryItem]

    /// Diagnostics surfaced to the extension when the archive can't be read.
    let loadedCount: Int
    let loadError: String?

    init?(bookmark: Data, displayName: String) {
        self.displayName = displayName
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        self.zipURL = url
        self.didStartAccess = url.startAccessingSecurityScopedResource()
        self.reader = ZipArchiveReader(archiveURL: url)
        do {
            self.entries = try reader.listEntries()
            self.loadedCount = entries.count
            self.loadError = nil
        } catch {
            self.entries = []
            self.loadedCount = 0
            self.loadError = "\(error)"
        }
    }

    deinit {
        if didStartAccess { zipURL.stopAccessingSecurityScopedResource() }
    }

    func rootName() -> String { displayName }

    func files() -> [FPFile] {
        entries
            .filter { !$0.isDirectory }
            .map { FPFile(path: $0.path, size: Int64($0.displayByteCount)) }
    }

    func extract(entryPath: String) throws -> URL {
        let name = (entryPath as NSString).lastPathComponent
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(name.isEmpty ? "file" : name)
        try reader.extractEntry(atPath: entryPath, to: dest)
        return dest
    }
}
