import XCTest
import ZIPFoundation
@testable import ZipLook

/// In-app Quick Look: the controller must extract only file entries and reproduce their
/// bytes at the temp URL handed to the preview panel.
@MainActor
final class QuickLookControllerTests: XCTestCase {

    private var tempDir: URL!
    private var archiveURL: URL!
    private let fileA = Data("preview me\n".utf8)
    private let fileB = Data((0..<300).map { UInt8($0 & 0xFF) })

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QLCtrlTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        archiveURL = tempDir.appendingPathComponent("fixture.zip")

        let archive = try Archive(url: archiveURL, accessMode: .create)
        try add(archive, "notes.txt", fileA)
        try add(archive, "folder/blob.bin", fileB)
        try archive.addEntry(with: "folder/", type: .directory,
                             uncompressedSize: Int64(0), provider: { _, _ in Data() })
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func add(_ archive: Archive, _ path: String, _ data: Data) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate) { position, size in
            let start = Int(position)
            guard start < data.count else { return Data() }
            return data.subdata(in: start..<min(start + size, data.count))
        }
    }

    func testPreviewsFilesOnlyAndExtractsExactBytes() throws {
        let all = try ZipArchiveReader(archiveURL: archiveURL).listEntries()
        let controller = QuickLookController(archiveURL: archiveURL)
        controller.selectionProvider = { all }   // "select everything"
        controller.refreshFromSelection()

        // Directory excluded; two files offered.
        XCTAssertEqual(controller.previewEntries.count, 2)
        XCTAssertTrue(controller.hasPreviewableSelection)

        // Each preview URL holds the exact entry bytes.
        for (i, entry) in controller.previewEntries.enumerated() {
            let url = try XCTUnwrap(controller.previewItemURL(at: i))
            let expected = entry.fileName == "notes.txt" ? fileA : fileB
            XCTAssertEqual(try Data(contentsOf: url), expected)
            XCTAssertEqual(url.lastPathComponent, entry.fileName)   // keeps real name/type
        }
        controller.cleanup()
    }

    func testNoPreviewableSelectionWhenOnlyDirectory() throws {
        let dirs = try ZipArchiveReader(archiveURL: archiveURL).listEntries()
            .filter { $0.isDirectory }
        let controller = QuickLookController(archiveURL: archiveURL)
        controller.selectionProvider = { dirs }
        controller.refreshFromSelection()
        XCTAssertFalse(controller.hasPreviewableSelection)
        XCTAssertEqual(controller.previewEntries.count, 0)
    }
}
