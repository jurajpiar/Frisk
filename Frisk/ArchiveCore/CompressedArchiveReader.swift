import Foundation
import SWCompression

/// Reads non-zip archives (tar, tar.gz/tgz, tar.bz2, tar.xz, gz, bz2, xz, 7z) via
/// SWCompression. These formats are parsed from memory, so a size guard avoids OOM on
/// very large archives (zip, which streams, uses `ZipArchiveReader` instead).
///
/// Listing reads metadata only where the format allows it: tar and 7z header walks
/// (`TarContainer.info` / `SevenZipContainer.info`) and the gzip ISIZE trailer. The
/// `tar.*` variants still decompress the outer stream to reach the tar headers, and
/// bz2/xz carry no size field, so those decompress to list.
///
/// Extraction decompresses once and caches the result for the reader's lifetime, so
/// pulling several entries out of the same archive (drag-out, Quick Look) pays the
/// decompression cost a single time.
final class CompressedArchiveReader: ArchiveReading {
    let archiveURL: URL

    init(archiveURL: URL) {
        self.archiveURL = archiveURL
    }

    private enum Format { case tar, tarGz, tarBz2, tarXz, gz, bz2, xz, sevenZip }

    /// Decompressed content, built on first extract and reused for later ones. Tar and
    /// 7z entries share one backing buffer, so this holds at most one decompressed copy
    /// of the archive; it is freed with the reader.
    private enum Payload {
        case tar([TarEntry])
        case sevenZip([SevenZipEntry])
        case single(Data)
    }

    private let payloadLock = NSLock()
    private var cachedPayload: Payload?

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

    func listEntries() throws -> [ArchiveEntryItem] {
        let data = try loadData()
        switch try detectFormat() {
        case .tar:      return tarEntries(try TarContainer.info(container: data))
        case .tarGz:    return tarEntries(try TarContainer.info(container: try GzipArchive.unarchive(archive: data)))
        case .tarBz2:   return tarEntries(try TarContainer.info(container: try BZip2.decompress(data: data)))
        case .tarXz:    return tarEntries(try TarContainer.info(container: try XZArchive.unarchive(archive: data)))
        case .sevenZip: return sevenZipEntries(try SevenZipContainer.info(container: data))
        case .gz:       return [singleFileEntry(size: try gzipUncompressedSize(data), stripping: ".gz")]
        case .bz2:      return [singleFileEntry(size: try BZip2.decompress(data: data).count, stripping: ".bz2")]
        case .xz:       return [singleFileEntry(size: try XZArchive.unarchive(archive: data).count, stripping: ".xz")]
        }
    }

    /// Uncompressed size from the gzip ISIZE trailer (last 4 bytes, little-endian),
    /// avoiding a full decompression just to list one row. ISIZE is modulo 2^32 and
    /// covers only the final member of a multi-member file — acceptable for a listing.
    private func gzipUncompressedSize(_ data: Data) throws -> Int {
        // 18 bytes = minimal valid gzip (10 header + 8 trailer); also check the magic
        // so a mislabelled file still fails at open time rather than at extraction.
        guard data.count >= 18,
              data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else {
            throw ArchiveReaderError.cannotOpen(archiveURL)
        }
        return data.suffix(4).reversed().reduce(0) { ($0 << 8) | Int($1) }
    }

    // MARK: - Extraction

    func extractEntry(atPath path: String, to destinationURL: URL) throws {
        // Zip-slip guard (same policy as ZipArchiveReader).
        let components = (path as NSString).pathComponents
        guard !components.contains(".."), !path.hasPrefix("/") else {
            throw ArchiveReaderError.unsafeEntryPath(path)
        }
        let bytes: Data
        switch try payload() {
        case .tar(let entries):
            guard let entry = entries.first(where: { $0.info.name == path }) else {
                throw ArchiveReaderError.entryNotFound(path)
            }
            bytes = entry.data ?? Data()
        case .sevenZip(let entries):
            guard let entry = entries.first(where: { $0.info.name == path }) else {
                throw ArchiveReaderError.entryNotFound(path)
            }
            bytes = entry.data ?? Data()
        case .single(let data):
            bytes = data
        }
        try bytes.write(to: destinationURL)
    }

    /// Returns the decompressed payload, building it on first use. The lock also
    /// serialises concurrent extracts so the archive is never decompressed twice.
    private func payload() throws -> Payload {
        payloadLock.lock()
        defer { payloadLock.unlock() }
        if let cached = cachedPayload { return cached }
        let data = try loadData()
        let built: Payload
        switch try detectFormat() {
        case .tar:      built = .tar(try TarContainer.open(container: data))
        case .tarGz:    built = .tar(try TarContainer.open(container: try GzipArchive.unarchive(archive: data)))
        case .tarBz2:   built = .tar(try TarContainer.open(container: try BZip2.decompress(data: data)))
        case .tarXz:    built = .tar(try TarContainer.open(container: try XZArchive.unarchive(archive: data)))
        case .sevenZip: built = .sevenZip(try SevenZipContainer.open(container: data))
        case .gz:       built = .single(try GzipArchive.unarchive(archive: data))
        case .bz2:      built = .single(try BZip2.decompress(data: data))
        case .xz:       built = .single(try XZArchive.unarchive(archive: data))
        }
        cachedPayload = built
        return built
    }

    // MARK: - Mapping helpers

    private func tarEntries(_ infos: [TarEntryInfo]) -> [ArchiveEntryItem] {
        infos.map { item(name: $0.name, isDir: $0.type == .directory,
                         size: $0.size, mtime: $0.modificationTime) }
    }

    private func sevenZipEntries(_ infos: [SevenZipEntryInfo]) -> [ArchiveEntryItem] {
        infos.map { item(name: $0.name, isDir: $0.type == .directory,
                         size: $0.size, mtime: $0.modificationTime) }
    }

    private func item(name: String, isDir: Bool, size: Int?, mtime: Date?) -> ArchiveEntryItem {
        ArchiveEntryItem(id: name, path: name, fileName: (name as NSString).lastPathComponent,
                     isDirectory: isDir, uncompressedSize: UInt64(max(0, size ?? 0)),
                     compressedSize: 0, modificationDate: mtime)
    }

    /// A single-file compressed archive (`foo.txt.gz`) lists as one entry named `foo.txt`.
    private func singleFileEntry(size: Int, stripping suffix: String) -> ArchiveEntryItem {
        var name = archiveURL.lastPathComponent
        if name.lowercased().hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        return item(name: name, isDir: false, size: size, mtime: nil)
    }
}
