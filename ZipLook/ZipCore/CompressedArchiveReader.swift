import Foundation
import SWCompression

/// Reads non-zip archives (tar, tar.gz/tgz, tar.bz2, tar.xz, gz, bz2, xz, 7z) via
/// SWCompression. These formats are parsed from memory, so a size guard avoids OOM on
/// very large archives (zip, which streams, uses `ZipArchiveReader` instead).
struct CompressedArchiveReader: ArchiveReading {
    let archiveURL: URL

    private enum Format { case tar, tarGz, tarBz2, tarXz, gz, bz2, xz, sevenZip }

    private func detectFormat() throws -> Format {
        let name = archiveURL.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz")  || name.hasSuffix(".tgz")  { return .tarGz }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") || name.hasSuffix(".tbz2") { return .tarBz2 }
        if name.hasSuffix(".tar.xz")  || name.hasSuffix(".txz")  { return .tarXz }
        if name.hasSuffix(".tar")  { return .tar }
        if name.hasSuffix(".7z")   { return .sevenZip }
        if name.hasSuffix(".gz")   { return .gz }
        if name.hasSuffix(".bz2")  { return .bz2 }
        if name.hasSuffix(".xz")   { return .xz }
        throw ArchiveReaderError.unsupportedFormat(name)
    }

    private func loadData() throws -> Data {
        let attrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        guard size <= ArchiveReaders.memoryFormatSizeCap else {
            throw ArchiveReaderError.archiveTooLarge(size)
        }
        return try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    }

    // MARK: - Listing

    func listEntries() throws -> [ZipEntryItem] {
        let data = try loadData()
        switch try detectFormat() {
        case .tar:      return tarEntries(try TarContainer.open(container: data))
        case .tarGz:    return tarEntries(try TarContainer.open(container: try GzipArchive.unarchive(archive: data)))
        case .tarBz2:   return tarEntries(try TarContainer.open(container: try BZip2.decompress(data: data)))
        case .tarXz:    return tarEntries(try TarContainer.open(container: try XZArchive.unarchive(archive: data)))
        case .sevenZip: return sevenZipEntries(try SevenZipContainer.open(container: data))
        case .gz:       return [singleFileEntry(size: try GzipArchive.unarchive(archive: data).count, stripping: ".gz")]
        case .bz2:      return [singleFileEntry(size: try BZip2.decompress(data: data).count, stripping: ".bz2")]
        case .xz:       return [singleFileEntry(size: try XZArchive.unarchive(archive: data).count, stripping: ".xz")]
        }
    }

    // MARK: - Extraction

    func extractEntry(atPath path: String, to destinationURL: URL) throws {
        // Zip-slip guard (same policy as ZipArchiveReader).
        let components = (path as NSString).pathComponents
        guard !components.contains(".."), !path.hasPrefix("/") else {
            throw ZipReaderError.unsafeEntryPath(path)
        }
        let data = try loadData()
        let bytes: Data
        switch try detectFormat() {
        case .tar:      bytes = try tarData(try TarContainer.open(container: data), path: path)
        case .tarGz:    bytes = try tarData(try TarContainer.open(container: try GzipArchive.unarchive(archive: data)), path: path)
        case .tarBz2:   bytes = try tarData(try TarContainer.open(container: try BZip2.decompress(data: data)), path: path)
        case .tarXz:    bytes = try tarData(try TarContainer.open(container: try XZArchive.unarchive(archive: data)), path: path)
        case .sevenZip: bytes = try sevenZipData(try SevenZipContainer.open(container: data), path: path)
        case .gz:       bytes = try GzipArchive.unarchive(archive: data)
        case .bz2:      bytes = try BZip2.decompress(data: data)
        case .xz:       bytes = try XZArchive.unarchive(archive: data)
        }
        try bytes.write(to: destinationURL)
    }

    // MARK: - Mapping helpers

    private func tarEntries(_ entries: [TarEntry]) -> [ZipEntryItem] {
        entries.map { item(name: $0.info.name, isDir: $0.info.type == .directory,
                           size: $0.info.size, mtime: $0.info.modificationTime) }
    }

    private func sevenZipEntries(_ entries: [SevenZipEntry]) -> [ZipEntryItem] {
        entries.map { item(name: $0.info.name, isDir: $0.info.type == .directory,
                           size: $0.info.size, mtime: $0.info.modificationTime) }
    }

    private func item(name: String, isDir: Bool, size: Int?, mtime: Date?) -> ZipEntryItem {
        ZipEntryItem(id: name, path: name, fileName: (name as NSString).lastPathComponent,
                     isDirectory: isDir, uncompressedSize: UInt64(max(0, size ?? 0)),
                     compressedSize: 0, modificationDate: mtime)
    }

    private func tarData(_ entries: [TarEntry], path: String) throws -> Data {
        guard let entry = entries.first(where: { $0.info.name == path }) else {
            throw ZipReaderError.entryNotFound(path)
        }
        return entry.data ?? Data()
    }

    private func sevenZipData(_ entries: [SevenZipEntry], path: String) throws -> Data {
        guard let entry = entries.first(where: { $0.info.name == path }) else {
            throw ZipReaderError.entryNotFound(path)
        }
        return entry.data ?? Data()
    }

    /// A single-file compressed archive (`foo.txt.gz`) lists as one entry named `foo.txt`.
    private func singleFileEntry(size: Int, stripping suffix: String) -> ZipEntryItem {
        var name = archiveURL.lastPathComponent
        if name.lowercased().hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        return item(name: name, isDir: false, size: size, mtime: nil)
    }
}
