import Foundation
import FileProvider
import os

let fpLog = Logger(subsystem: "org.deadkittens.ZipLook.FileProvider", category: "fp")

/// Read-only `NSFileProviderReplicatedExtension` that presents an archive as a file tree.
/// M2 uses `StaticBackend` to prove enumeration/materialisation; M3 swaps in a zip backend.
final class ZipFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let backend: ProviderBackend
    private let tree: FPTree

    required init(domain: NSFileProviderDomain) {
        // Pick the backend for this domain: its registered zip, else a diagnostic tree
        // that reports why (visible as a filename in the mount).
        let did = domain.identifier.rawValue
        // Resolve the domain's security-scoped bookmark (shared via App Group UserDefaults)
        // and read the user's original zip.
        if let bookmark = ZipDomainStore.bookmark(forDomainID: did) {
            if let zip = ZipBackend(bookmark: bookmark, displayName: domain.displayName), zip.loadedCount > 0 {
                self.backend = zip
            } else {
                let zip = ZipBackend(bookmark: bookmark, displayName: domain.displayName)
                let detail = zip == nil ? "resolve-FAIL" : "read0-\(zip!.loadError ?? "empty")"
                self.backend = DiagnosticBackend(reason: "bm-\(bookmark.count)b-\(detail)")
            }
        } else {
            // Probe the bookmark file directly to see what the extension can access.
            let f = ZipDomainStore.containerURL()?
                .appendingPathComponent("bookmarks").appendingPathComponent("\(did).bookmark")
            let exists = f.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            var readInfo = "noURL"
            if let f {
                do { let d = try Data(contentsOf: f); readInfo = "read\(d.count)B" }
                catch { readInfo = "readERR" }
            }
            self.backend = DiagnosticBackend(reason: "nobm-exists\(exists)-\(readInfo)-ids\(ZipDomainStore.allDomainIDs().count)")
        }
        self.tree = FPTree(rootName: backend.rootName(), files: backend.files())
        super.init()
        fpLog.log("init(domain: \(domain.identifier.rawValue, privacy: .public)) backend=\(String(describing: type(of: self.backend)), privacy: .public) nodes=\(self.tree.nodes.count)")
    }

    func invalidate() { fpLog.log("invalidate") }

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        fpLog.log("item(for: \(identifier.rawValue, privacy: .public))")
        if let node = tree.node(for: identifier) {
            completionHandler(ZipProviderItem(node), nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        fpLog.log("fetchContents(\(itemIdentifier.rawValue, privacy: .public))")
        guard let node = tree.node(for: itemIdentifier), !node.isDirectory, let entryPath = node.entryPath else {
            completionHandler(nil, nil, NSFileProviderError(.noSuchItem)); return Progress()
        }
        do {
            let url = try backend.extract(entryPath: entryPath)
            completionHandler(url, ZipProviderItem(node), nil)
        } catch {
            fpLog.error("fetchContents failed: \(error.localizedDescription, privacy: .public)")
            completionHandler(nil, nil, error)
        }
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        fpLog.log("enumerator(for: \(containerItemIdentifier.rawValue, privacy: .public))")
        return ZipEnumerator(container: containerItemIdentifier, tree: tree)
    }

    // MARK: - Read-only: mutating operations are unsupported.
    private var unsupported: NSError { NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError) }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields,
                    contents url: URL?, options: NSFileProviderCreateItemOptions = [],
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, unsupported); return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, unsupported); return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(unsupported); return Progress()
    }
}
