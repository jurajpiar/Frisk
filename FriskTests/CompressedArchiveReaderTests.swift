import XCTest
import SWCompression
@testable import Frisk

/// Exercises the SWCompression-backed reader for the non-zip formats. Fixtures are built
/// in-process with SWCompression itself (no external CLI tools), so the tests are
/// self-contained and deterministic across machines and CI.
final class CompressedArchiveReaderTests: XCTestCase {

    private var tempDir: URL!

    private let firstData = Data("Hello, Frisk!\n".utf8)
    private let secondData = Data((0..<512).map { UInt8($0 & 0xFF) })

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompressedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    // MARK: - Fixture builders

    /// A tar container with two files and one directory entry.
    private func makeTarData() throws -> Data {
        let entries: [TarEntry] = [
            TarEntry(info: TarEntryInfo(name: "first.txt", type: .regular), data: firstData),
            TarEntry(info: TarEntryInfo(name: "nested/second.bin", type: .regular), data: secondData),
            TarEntry(info: TarEntryInfo(name: "nested/", type: .directory), data: nil),
        ]
        return TarContainer.create(from: entries)
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - Container formats (tar / tgz / tbz2)

    private func assertContainerLists(_ url: URL) throws {
        let reader = ArchiveReaders.reader(for: url)
        XCTAssertTrue(reader is CompressedArchiveReader)
        let entries = try reader.listEntries()
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        let first = try XCTUnwrap(byPath["first.txt"])
        XCTAssertFalse(first.isDirectory)
        XCTAssertEqual(first.uncompressedSize, UInt64(firstData.count))

        let second = try XCTUnwrap(byPath["nested/second.bin"])
        XCTAssertEqual(second.uncompressedSize, UInt64(secondData.count))

        let dir = try XCTUnwrap(byPath["nested/"])
        XCTAssertTrue(dir.isDirectory)
    }

    private func assertContainerExtracts(_ url: URL) throws {
        let reader = ArchiveReaders.reader(for: url)
        let out = tempDir.appendingPathComponent("out-\(UUID().uuidString).bin")
        try reader.extractEntry(atPath: "nested/second.bin", to: out)
        XCTAssertEqual(try Data(contentsOf: out), secondData)
    }

    func testTarListAndExtract() throws {
        let url = try write(try makeTarData(), as: "fixture.tar")
        try assertContainerLists(url)
        try assertContainerExtracts(url)
    }

    func testTgzListAndExtract() throws {
        let gz = try GzipArchive.archive(data: try makeTarData())
        let url = try write(gz, as: "fixture.tgz")
        try assertContainerLists(url)
        try assertContainerExtracts(url)
    }

    func testTarBz2ListAndExtract() throws {
        let bz = try BZip2.compress(data: try makeTarData())
        let url = try write(bz, as: "fixture.tar.bz2")
        try assertContainerLists(url)
        try assertContainerExtracts(url)
    }

    // MARK: - Single-file formats (gz / bz2)

    func testGzSingleFile() throws {
        let gz = try GzipArchive.archive(data: firstData)
        let url = try write(gz, as: "note.txt.gz")
        let reader = ArchiveReaders.reader(for: url)

        let entries = try reader.listEntries()
        XCTAssertEqual(entries.count, 1)
        // The single entry is named with the compression suffix stripped.
        XCTAssertEqual(entries.first?.fileName, "note.txt")
        XCTAssertEqual(entries.first?.uncompressedSize, UInt64(firstData.count))

        let out = tempDir.appendingPathComponent("note.txt")
        try reader.extractEntry(atPath: entries[0].path, to: out)
        XCTAssertEqual(try Data(contentsOf: out), firstData)
    }

    func testBz2SingleFile() throws {
        let bz = try BZip2.compress(data: firstData)
        let url = try write(bz, as: "note.txt.bz2")
        let reader = ArchiveReaders.reader(for: url)

        let entries = try reader.listEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.fileName, "note.txt")

        let out = tempDir.appendingPathComponent("note-out.txt")
        try reader.extractEntry(atPath: entries[0].path, to: out)
        XCTAssertEqual(try Data(contentsOf: out), firstData)
    }

    // MARK: - Real-world fixtures (formats SWCompression can't create in-process)

    /// Locate a checked-in fixture in the test bundle.
    private func fixture(_ name: String, _ ext: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        return try XCTUnwrap(bundle.url(forResource: name, withExtension: ext),
                             "missing fixture \(name).\(ext) in test bundle")
    }

    /// `.7z` — SWCompression is read-only for 7z, so this uses a real archive built by
    /// libarchive (bsdtar --format 7zip). Verifies list + exact-bytes extraction.
    func testSevenZipFixture() throws {
        let url = try fixture("fixture", "7z")
        let reader = ArchiveReaders.reader(for: url)
        XCTAssertTrue(reader is CompressedArchiveReader)

        let entries = try reader.listEntries()
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let first = try XCTUnwrap(byPath["first.txt"])
        XCTAssertEqual(first.uncompressedSize, UInt64(firstData.count))
        let second = try XCTUnwrap(byPath["nested/second.bin"])
        XCTAssertEqual(second.uncompressedSize, UInt64(secondData.count))

        let out = tempDir.appendingPathComponent("7z-out.bin")
        try reader.extractEntry(atPath: "nested/second.bin", to: out)
        XCTAssertEqual(try Data(contentsOf: out), secondData)
    }

    /// `.xz` — no xz encoder in SWCompression, so this uses a real single-file stream
    /// produced by the `xz` tool. Lists as one entry with the `.xz` suffix stripped.
    func testXzFixture() throws {
        let url = try fixture("note.txt", "xz")
        let reader = ArchiveReaders.reader(for: url)
        XCTAssertTrue(reader is CompressedArchiveReader)

        let entries = try reader.listEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.fileName, "note.txt")

        let out = tempDir.appendingPathComponent("xz-out.txt")
        try reader.extractEntry(atPath: entries[0].path, to: out)
        XCTAssertEqual(try Data(contentsOf: out), firstData)
    }

    // MARK: - Guards

    func testZipSlipPathRejected() throws {
        let url = try write(try makeTarData(), as: "fixture.tar")
        let reader = ArchiveReaders.reader(for: url)
        let out = tempDir.appendingPathComponent("escape")
        XCTAssertThrowsError(try reader.extractEntry(atPath: "../escape", to: out)) { error in
            guard case ArchiveReaderError.unsafeEntryPath = error else {
                return XCTFail("expected unsafeEntryPath, got \(error)")
            }
        }
    }

    func testMissingEntryThrows() throws {
        let url = try write(try makeTarData(), as: "fixture.tar")
        let reader = ArchiveReaders.reader(for: url)
        let out = tempDir.appendingPathComponent("nope")
        XCTAssertThrowsError(try reader.extractEntry(atPath: "does-not-exist.txt", to: out)) { error in
            guard case ArchiveReaderError.entryNotFound = error else {
                return XCTFail("expected entryNotFound, got \(error)")
            }
        }
    }

    // MARK: - Format routing

    func testReaderFactoryRouting() {
        func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }
        XCTAssertTrue(ArchiveReaders.reader(for: url("a.zip")) is ZipArchiveReader)
        for name in ["a.tar", "a.tgz", "a.tar.gz", "a.tar.bz2", "a.tar.xz",
                     "a.7z", "a.gz", "a.bz2", "a.xz"] {
            XCTAssertTrue(ArchiveReaders.reader(for: url(name)) is CompressedArchiveReader,
                          "\(name) should route to CompressedArchiveReader")
        }
    }

    func testIsSupportedArchive() {
        func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }
        for name in ["a.zip", "a.tar", "a.tgz", "a.tar.gz", "a.7z", "a.xz", "a.bz2"] {
            XCTAssertTrue(ArchiveReaders.isSupportedArchive(url(name)), "\(name) should be supported")
        }
        for name in ["a.txt", "a.png", "a.tarx", "a"] {
            XCTAssertFalse(ArchiveReaders.isSupportedArchive(url(name)), "\(name) should be unsupported")
        }
    }
}
