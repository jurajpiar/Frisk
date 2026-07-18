import AppKit
import Quartz   // QLPreviewPanel, QLPreviewItem, QLPreviewPanelDataSource/Delegate

/// Drives the shared `QLPreviewPanel` so the app can preview a selected entry's contents
/// the way Finder's spacebar does. `QLPreviewPanel` previews file URLs, so each entry is
/// extracted to a temporary file on demand (and cached) before being handed to the panel.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let archiveURL: URL
    private let reader: ArchiveReading
    private let tempRoot: URL
    private var extracted: [String: URL] = [:]   // entry path -> extracted temp file URL

    /// The file entries currently offered to the panel (snapshot of the selection).
    private(set) var previewEntries: [ZipEntryItem] = []

    /// Supplies the current table selection (set by the table view).
    var selectionProvider: () -> [ZipEntryItem] = { [] }
    /// The table, so the panel can forward arrow keys to move the selection.
    weak var tableView: NSTableView?

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
        self.reader = ArchiveReaders.reader(for: archiveURL)
        self.tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipLookQL-\(UUID().uuidString)", isDirectory: true)
        super.init()
    }

    deinit { cleanup() }

    /// Whether the current selection has anything previewable (a non-directory entry).
    var hasPreviewableSelection: Bool {
        selectionProvider().contains { !$0.isDirectory }
    }

    /// Snapshot the selection (files only) for the panel to display.
    func refreshFromSelection() {
        previewEntries = selectionProvider().filter { !$0.isDirectory }
    }

    /// Remove all extracted temporary files.
    func cleanup() {
        try? FileManager.default.removeItem(at: tempRoot)
        extracted.removeAll()
    }

    /// The temp URL of the previewable entry at `index`, extracting it if needed.
    /// Exposed for testing; `previewPanel(_:previewItemAt:)` uses it.
    func previewItemURL(at index: Int) -> URL? {
        guard index >= 0, index < previewEntries.count else { return nil }
        return url(for: previewEntries[index])
    }

    /// File entries in the current selection.
    func selectedFiles() -> [ZipEntryItem] { selectionProvider().filter { !$0.isDirectory } }

    /// Extract `entry` to a temp file and return its URL (for the in-app markdown preview
    /// and its "Open with…" button).
    func extractedURL(for entry: ZipEntryItem) -> URL? { url(for: entry) }

    /// Extract (once) the entry to a temp file and return its URL.
    private func url(for entry: ZipEntryItem) -> URL? {
        if let cached = extracted[entry.path] { return cached }
        // Each entry gets its own subdirectory so the extracted file keeps its real name
        // (and name collisions between different paths can't clash).
        let dir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let name = entry.fileName.isEmpty ? "file" : entry.fileName
        let dest = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let didAccess = archiveURL.startAccessingSecurityScopedResource()
            defer { if didAccess { archiveURL.stopAccessingSecurityScopedResource() } }
            try reader.extractEntry(atPath: entry.path, to: dest)
            extracted[entry.path] = dest
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { previewEntries.count }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        guard let url = previewItemURL(at: index) else {
            return tempRoot as NSURL   // benign fallback; shows nothing rather than crashing
        }
        return url as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    /// Forward key presses (arrows) from the panel back to the table so the selection —
    /// and thus the previewed item — tracks the keyboard, as in Finder.
    func previewPanel(_ panel: QLPreviewPanel, handle event: NSEvent) -> Bool {
        guard event.type == .keyDown, let tableView else { return false }
        tableView.keyDown(with: event)
        refreshFromSelection()
        panel.reloadData()
        return true
    }
}
