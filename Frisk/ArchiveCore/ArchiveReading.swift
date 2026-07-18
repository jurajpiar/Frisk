import Foundation

/// A read-only archive: list its entries from metadata and extract a single entry.
/// Implemented by `ZipArchiveReader` (zip, via ZIPFoundation) and `CompressedArchiveReader`
/// (tar/gzip/bzip2/xz/7z, via SWCompression).
protocol ArchiveReading {
    func listEntries() throws -> [ArchiveEntryItem]
    func extractEntry(atPath path: String, to destinationURL: URL) throws
}

enum ArchiveReaderError: Error {
    case unsupportedFormat(String)
    case archiveTooLarge(UInt64)
    case cannotOpen(URL)
    case entryNotFound(String)
    case unsafeEntryPath(String)
}

enum ArchiveReaders {
    /// Cap for memory-parsed (non-zip) archives — these formats are read whole into RAM,
    /// so refuse very large ones to avoid OOM. Zip streams via ZipArchiveReader (no cap).
    static let memoryFormatSizeCap: UInt64 = 300 * 1024 * 1024   // 300 MB

    /// Extensions handled by the non-zip (SWCompression) backend.
    static let compressedExtensions: [String] = [
        ".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tbz2", ".tar.xz", ".txz",
        ".tar", ".7z", ".gz", ".bz2", ".xz"
    ]

    /// All archive filename extensions Frisk can open (zip + the above).
    static func isSupportedArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".zip") || compressedExtensions.contains { name.hasSuffix($0) }
    }

    /// Pick a reader for the archive by filename extension.
    static func reader(for url: URL) -> ArchiveReading {
        url.lastPathComponent.lowercased().hasSuffix(".zip")
            ? ZipArchiveReader(archiveURL: url)
            : CompressedArchiveReader(archiveURL: url)
    }
}
