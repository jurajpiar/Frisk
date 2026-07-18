import Foundation
import FileProvider
import UniformTypeIdentifiers

/// Bridges an `FPNode` to `NSFileProviderItem`. Read-only; every item supplies an
/// `itemVersion` (required for replicated extensions).
final class ZipProviderItem: NSObject, NSFileProviderItem {
    private let node: FPNode
    init(_ node: FPNode) { self.node = node }

    var itemIdentifier: NSFileProviderItemIdentifier { node.identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { node.parent }
    var filename: String { node.filename }

    var contentType: UTType {
        if node.isDirectory { return .folder }
        let ext = (node.filename as NSString).pathExtension
        return UTType(filenameExtension: ext) ?? .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        node.isDirectory ? [.allowsContentEnumerating, .allowsReading] : [.allowsReading]
    }

    var itemVersion: NSFileProviderItemVersion {
        // Content is immutable for a given archive, so a constant version is correct.
        NSFileProviderItemVersion(contentVersion: Data("1".utf8), metadataVersion: Data("1".utf8))
    }

    var documentSize: NSNumber? { node.isDirectory ? nil : NSNumber(value: node.size) }
}

/// Enumerates the children of one container.
final class ZipEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let tree: FPTree

    init(container: NSFileProviderItemIdentifier, tree: FPTree) {
        self.container = container
        self.tree = tree
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        // The working set (offline/spotlight cache) is left empty for a read-only browser.
        let items: [NSFileProviderItem]
        if container == .workingSet {
            items = []
        } else {
            items = tree.children(of: container).map { ZipProviderItem($0) }
        }
        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // Static archive: no changes.
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("1".utf8)))
    }
}
