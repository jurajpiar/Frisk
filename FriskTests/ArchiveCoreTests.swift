import XCTest
import ZIPFoundation
@testable import Frisk

final class ArchiveCoreTests: XCTestCase {

    private var tempDir: URL!
    private var archiveURL: URL!

    // Known fixture payloads.
    private let firstData = Data("Hello, Frisk!\n".utf8)
    private let secondData = Data((0..<512).map { UInt8($0 & 0xFF) })  // 512 bytes

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        archiveURL = tempDir.appendingPathComponent("fixture.zip")

        // Build a fixture archive: 2 files + 1 nested directory entry.
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try addFile(archive, path: "first.txt", data: firstData)
        try addFile(archive, path: "nested/second.bin", data: secondData)
        try archive.addEntry(with: "nested/", type: .directory,
                             uncompressedSize: Int64(0), provider: { _, _ in Data() })
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func addFile(_ archive: Archive, path: String, data: Data) throws {
        try archive.addEntry(with: path, type: .file,
                             uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate) { position, size in
            let start = Int(position)
            guard start < data.count else { return Data() }
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }

    // MARK: - listEntries

    func testListEntriesReturnsExpectedEntries() throws {
        let reader = ZipArchiveReader(archiveURL: archiveURL)
        let entries = try reader.listEntries()

        // At least the 3 entries we wrote.
        XCTAssertGreaterThanOrEqual(entries.count, 3)

        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        let first = try XCTUnwrap(byPath["first.txt"])
        XCTAssertEqual(first.fileName, "first.txt")
        XCTAssertFalse(first.isDirectory)
        XCTAssertEqual(first.uncompressedSize, UInt64(firstData.count))

        let second = try XCTUnwrap(byPath["nested/second.bin"])
        XCTAssertEqual(second.fileName, "second.bin")
        XCTAssertFalse(second.isDirectory)
        XCTAssertEqual(second.uncompressedSize, UInt64(secondData.count))

        let dir = try XCTUnwrap(byPath["nested/"])
        XCTAssertTrue(dir.isDirectory)
    }

    // MARK: - extractEntry

    func testExtractEntryReproducesBytesExactly() throws {
        let reader = ZipArchiveReader(archiveURL: archiveURL)
        let dest = tempDir.appendingPathComponent("extracted-second.bin")
        try reader.extractEntry(atPath: "nested/second.bin", to: dest)

        let roundTripped = try Data(contentsOf: dest)
        XCTAssertEqual(roundTripped, secondData)
    }

    func testExtractEntryThrowsForMissingEntry() {
        let reader = ZipArchiveReader(archiveURL: archiveURL)
        let dest = tempDir.appendingPathComponent("nope")
        XCTAssertThrowsError(try reader.extractEntry(atPath: "does/not/exist", to: dest)) { error in
            guard case ArchiveReaderError.entryNotFound = error else {
                return XCTFail("expected entryNotFound, got \(error)")
            }
        }
    }

    // MARK: - Zip-slip guard

    func testExtractEntryRejectsTraversalPath() {
        let reader = ZipArchiveReader(archiveURL: archiveURL)
        let dest = tempDir.appendingPathComponent("slip")
        XCTAssertThrowsError(try reader.extractEntry(atPath: "../../etc/passwd", to: dest)) { error in
            guard case ArchiveReaderError.unsafeEntryPath = error else {
                return XCTFail("expected unsafeEntryPath, got \(error)")
            }
        }
    }

    func testExtractEntryRejectsAbsolutePath() {
        let reader = ZipArchiveReader(archiveURL: archiveURL)
        let dest = tempDir.appendingPathComponent("slip-abs")
        XCTAssertThrowsError(try reader.extractEntry(atPath: "/etc/passwd", to: dest)) { error in
            guard case ArchiveReaderError.unsafeEntryPath = error else {
                return XCTFail("expected unsafeEntryPath, got \(error)")
            }
        }
    }
}
