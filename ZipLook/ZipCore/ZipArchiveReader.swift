import Foundation
import ZIPFoundation

enum ZipReaderError: Error {
    case cannotOpen(URL)
    case entryNotFound(String)
    case unsafeEntryPath(String)
}

/// Reads a zip archive's central directory and extracts individual entries.
/// Opening never inflates entry data; only `extractEntry(atPath:to:)` writes bytes.
///
/// Adapted to ZIPFoundation 0.9.20: `Archive(url:accessMode:)` is a *throwing*
/// initialiser, and `Entry.uncompressedSize` / `compressedSize` are already `UInt64`.
struct ZipArchiveReader: ArchiveReading {
    let archiveURL: URL

    /// Lists entries by reading the central directory only — no data is inflated.
    func listEntries() throws -> [ZipEntryItem] {
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            // Normalise any open/parse failure into a single, reportable error.
            throw ZipReaderError.cannotOpen(archiveURL)
        }
        return archive.map { entry in
            ZipEntryItem(
                id: entry.path,
                path: entry.path,
                fileName: (entry.path as NSString).lastPathComponent,
                isDirectory: entry.type == .directory,
                uncompressedSize: entry.uncompressedSize,
                compressedSize: entry.compressedSize,
                modificationDate: entry.fileAttributes[.modificationDate] as? Date
            )
        }
    }

    /// Extracts exactly one entry to `destinationURL` (a full file URL including filename).
    func extractEntry(atPath path: String, to destinationURL: URL) throws {
        // Zip-slip guard: reject traversal components in the entry path.
        let components = (path as NSString).pathComponents
        guard !components.contains(".."), !path.hasPrefix("/") else {
            throw ZipReaderError.unsafeEntryPath(path)
        }
        let archive = try Archive(url: archiveURL, accessMode: .read)
        guard let entry = archive[path] else {
            throw ZipReaderError.entryNotFound(path)
        }
        _ = try archive.extract(entry, to: destinationURL)
    }
}
