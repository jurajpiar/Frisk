import Foundation
import FileProvider

/// A flat file entry (path relative to the archive root + uncompressed size).
struct FPFile {
    let path: String     // e.g. "docs/notes.md"
    let size: Int64
}

/// A node in the materialised file tree presented to Finder.
struct FPNode {
    let identifier: NSFileProviderItemIdentifier
    let parent: NSFileProviderItemIdentifier
    let filename: String
    let isDirectory: Bool
    let size: Int64
    let entryPath: String?   // zip entry path for files; nil for synthesised dirs / root
}

/// Builds and serves a hierarchical tree from a flat list of file paths, synthesising
/// intermediate directory nodes for path prefixes the archive omits.
struct FPTree {
    private(set) var nodes: [NSFileProviderItemIdentifier: FPNode] = [:]
    private(set) var childrenByParent: [NSFileProviderItemIdentifier: [NSFileProviderItemIdentifier]] = [:]

    /// Identifier for a directory prefix like "docs/" → stable string id; root → .rootContainer.
    static func identifier(forDirectoryPath dir: String) -> NSFileProviderItemIdentifier {
        dir.isEmpty ? .rootContainer : NSFileProviderItemIdentifier(dir)
    }

    init(rootName: String, files: [FPFile]) {
        // Root container.
        nodes[.rootContainer] = FPNode(identifier: .rootContainer, parent: .rootContainer,
                                       filename: rootName, isDirectory: true, size: 0, entryPath: nil)

        for file in files {
            let comps = file.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !comps.isEmpty else { continue }
            // Ensure directory chain exists.
            var prefix = ""
            var parent: NSFileProviderItemIdentifier = .rootContainer
            for dir in comps.dropLast() {
                prefix += dir + "/"
                let id = Self.identifier(forDirectoryPath: prefix)
                if nodes[id] == nil {
                    nodes[id] = FPNode(identifier: id, parent: parent, filename: dir,
                                       isDirectory: true, size: 0, entryPath: nil)
                    childrenByParent[parent, default: []].append(id)
                }
                parent = id
            }
            // The file leaf. Skip pure-directory entries (path ending in "/").
            if file.path.hasSuffix("/") { continue }
            let fileID = NSFileProviderItemIdentifier(file.path)
            if nodes[fileID] == nil {
                nodes[fileID] = FPNode(identifier: fileID, parent: parent,
                                       filename: comps.last!, isDirectory: false,
                                       size: file.size, entryPath: file.path)
                childrenByParent[parent, default: []].append(fileID)
            }
        }
    }

    func node(for id: NSFileProviderItemIdentifier) -> FPNode? { nodes[id] }
    func children(of id: NSFileProviderItemIdentifier) -> [FPNode] {
        (childrenByParent[id] ?? []).compactMap { nodes[$0] }
    }
}
