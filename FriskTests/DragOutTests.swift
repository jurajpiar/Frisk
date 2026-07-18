import XCTest
import AppKit
import UniformTypeIdentifiers
import ZIPFoundation
@testable import Frisk

/// Stage 04 invariants that can be checked without a live drag gesture. The actual
/// drag/drop, Esc-cancel and large-file responsiveness are the human gate.
@MainActor
final class DragOutTests: XCTestCase {

    private var tempDir: URL!
    private var archiveURL: URL!
    private let fileData = Data((0..<4096).map { UInt8($0 & 0xFF) })

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragOutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        archiveURL = tempDir.appendingPathComponent("fixture.zip")

        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "folder/payload.bin", type: .file,
                             uncompressedSize: Int64(fileData.count),
                             compressionMethod: .deflate) { position, size in
            let start = Int(position)
            guard start < self.fileData.count else { return Data() }
            let end = min(start + size, self.fileData.count)
            return self.fileData.subdata(in: start..<end)
        }
        try archive.addEntry(with: "folder/", type: .directory,
                             uncompressedSize: Int64(0), provider: { _, _ in Data() })
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func entries() throws -> [ArchiveEntryItem] {
        try ZipArchiveReader(archiveURL: archiveURL).listEntries()
    }

    // MARK: - Files-only drag rule

    func testDirectoryRowIsNotDraggable() throws {
        let all = try entries()
        let dirIndex = try XCTUnwrap(all.firstIndex { $0.isDirectory })
        let coordinator = EntryTableView.Coordinator(entries: all, archiveURL: archiveURL)
        let writer = coordinator.tableView(NSTableView(), pasteboardWriterForRow: dirIndex)
        XCTAssertNil(writer, "directories must not be draggable in v1")
    }

    func testFileRowProducesPromiseCarryingEntryPath() throws {
        let all = try entries()
        let fileIndex = try XCTUnwrap(all.firstIndex { !$0.isDirectory })
        let coordinator = EntryTableView.Coordinator(entries: all, archiveURL: archiveURL)
        let writer = coordinator.tableView(NSTableView(), pasteboardWriterForRow: fileIndex)
        let provider = try XCTUnwrap(writer as? NSFilePromiseProvider)
        XCTAssertEqual(provider.userInfo as? String, all[fileIndex].path)
    }

    // MARK: - Extraction happens only on the promise write, and is byte-exact

    func testWritePromiseExtractsExactBytes() throws {
        let delegate = ArchiveFilePromiseDelegate(archiveURL: archiveURL)
        let provider = NSFilePromiseProvider(fileType: UTType.data.identifier, delegate: delegate)
        provider.userInfo = "folder/payload.bin"

        // The suggested filename is the entry's last path component.
        XCTAssertEqual(delegate.filePromiseProvider(provider, fileNameForType: UTType.data.identifier),
                       "payload.bin")

        let dest = tempDir.appendingPathComponent("payload.bin")
        let done = expectation(description: "promise write completes")
        var writeError: Error?
        delegate.filePromiseProvider(provider, writePromiseTo: dest) { error in
            writeError = error
            done.fulfill()
        }
        wait(for: [done], timeout: 5)

        XCTAssertNil(writeError)
        XCTAssertEqual(try Data(contentsOf: dest), fileData, "dropped bytes must match the entry exactly")
    }
}
