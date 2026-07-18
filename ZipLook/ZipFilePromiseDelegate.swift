import AppKit

/// Supplies a single zip entry to a drop destination. Nothing is extracted until the
/// drop lands — `filePromiseProvider(_:writePromiseTo:completionHandler:)` is the only
/// call site that writes bytes (D6). Extraction runs on a private serial queue, never
/// the main thread.
final class ZipFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let archiveURL: URL
    private let reader: ArchiveReading

    /// Serial background queue that the system uses to fulfil promise writes.
    private let workQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.deadkittens.ZipLook.promiseWrites"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
        self.reader = ArchiveReaders.reader(for: archiveURL)
    }

    /// The filename the dropped file should take (last path component of the entry).
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        let path = (filePromiseProvider.userInfo as? String) ?? "file"
        return path.components(separatedBy: "/").last ?? "file"
    }

    /// Extract exactly the promised entry to the system-supplied, sandbox-extended `url`.
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let entryPath = filePromiseProvider.userInfo as? String else {
            completionHandler(ZipReaderError.entryNotFound("?"))
            return
        }
        // Re-assert read access to the source archive for this write (persistent for
        // user-selected grants; correct if a bookmarked URL is ever used, D7).
        let didAccess = archiveURL.startAccessingSecurityScopedResource()
        defer { if didAccess { archiveURL.stopAccessingSecurityScopedResource() } }
        do {
            try reader.extractEntry(atPath: entryPath, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
            // A failure here is a real, user-initiated drop that went wrong — surface it.
            let name = path(from: filePromiseProvider)
            DispatchQueue.main.async {
                Self.presentExtractionFailure(entryName: name, error: error)
            }
        }
    }

    private func path(from provider: NSFilePromiseProvider) -> String {
        let full = (provider.userInfo as? String) ?? "file"
        return full.components(separatedBy: "/").last ?? "file"
    }

    /// Show a non-fatal alert explaining why a dragged entry could not be extracted.
    /// (Stage 06, step 1.)
    @MainActor
    static func presentExtractionFailure(entryName: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not extract “\(entryName)”"
        alert.informativeText = informativeText(for: error)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// British-English explanation, with a specific note for the password-protected case.
    static func informativeText(for error: Error) -> String {
        // ZIPFoundation 0.9.20 omits encrypted entries from the listing, so an encrypted
        // entry usually surfaces as "not found" at extraction time.
        if case ZipReaderError.entryNotFound = error {
            return "This entry could not be read. If the archive is encrypted, note that "
                 + "ZipLook cannot extract password-protected entries yet."
        }
        return "ZipLook could not extract this entry.\n\n\(error.localizedDescription)"
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        workQueue
    }
}
