import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the currently-open archive and the result of listing its entries.
/// Listing runs off the main thread; the published `state` drives the UI.
@MainActor
final class ArchiveStore: ObservableObject {
    /// Shared instance so the `NSApplicationDelegate` (Finder opens) and the SwiftUI
    /// scene (File -> Open, `.onOpenURL`) feed the same store.
    static let shared = ArchiveStore()

    enum LoadState: Sendable {
        case empty
        case loading
        case loaded([ArchiveEntryItem])
        case failed(String)
    }

    @Published private(set) var archiveURL: URL?
    @Published private(set) var state: LoadState = .empty

    private init() {}

    /// Archive types the Open panel accepts (zip + the SWCompression-backed formats).
    static let openableContentTypes: [UTType] = {
        var types: [UTType] = [.zip]
        for ext in ["tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "7z"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()

    /// Present an open panel restricted to supported archives (user-selected read grant, D7).
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.openableContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    /// Set the archive and (re)load its entry list off the main thread.
    func open(_ url: URL) {
        archiveURL = url
        state = .loading
        Task {
            let result = await Self.load(url)
            self.state = result
        }
    }

    /// Reads the central directory on a background executor (nonisolated async).
    private nonisolated static func load(_ url: URL) async -> LoadState {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let reader = ArchiveReaders.reader(for: url)
        do {
            let entries = try reader.listEntries()
            return .loaded(entries)
        } catch {
            return .failed(message(for: error))
        }
    }

    /// Human-readable, British-English error text for the error state.
    private nonisolated static func message(for error: Error) -> String {
        switch error {
        case ArchiveReaderError.cannotOpen:
            return "Could not open this file as a zip archive. It may be corrupt, "
                 + "encrypted at the container level, or not a zip file at all."
        case ArchiveReaderError.entryNotFound(let path):
            return "An expected entry was missing from the archive: \(path)."
        case ArchiveReaderError.unsafeEntryPath(let path):
            return "The archive contains an unsafe entry path and was not read: \(path)."
        default:
            return "The archive could not be read.\n\n\(error.localizedDescription)"
        }
    }
}
