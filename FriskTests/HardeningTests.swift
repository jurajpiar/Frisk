import XCTest
import AppKit
import ZIPFoundation
@testable import Frisk

/// Stage 06 checks that are self-contained (build the fixture in the sandbox temp dir).
/// Encrypted / non-UTF-8 / Zip64 archives are exercised via app-launch fixtures instead,
/// because they need external tooling to construct — see 06_hardening/outputs/STATUS.md.
@MainActor
final class HardeningTests: XCTestCase {

    private var tempDir: URL!
    private var archiveURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HardeningTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        archiveURL = tempDir.appendingPathComponent("multi.zip")

        let archive = try Archive(url: archiveURL, accessMode: .create)
        for i in 0..<3 {
            let data = Data("payload-\(i)".utf8)
            try archive.addEntry(with: "file-\(i).txt", type: .file,
                                 uncompressedSize: Int64(data.count),
                                 compressionMethod: .deflate) { position, size in
                let start = Int(position)
                guard start < data.count else { return Data() }
                return data.subdata(in: start..<min(start + size, data.count))
            }
        }
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    /// Step 4: selecting several rows and dragging yields one promise per row.
    func testEachRowProducesItsOwnPromise() throws {
        let entries = try ZipArchiveReader(archiveURL: archiveURL).listEntries()
            .filter { !$0.isDirectory }
        XCTAssertEqual(entries.count, 3)

        let coordinator = EntryTableView.Coordinator(entries: entries, archiveURL: archiveURL)
        let table = NSTableView()

        var providers: [NSFilePromiseProvider] = []
        for row in 0..<entries.count {
            let writer = coordinator.tableView(table, pasteboardWriterForRow: row)
            providers.append(try XCTUnwrap(writer as? NSFilePromiseProvider))
        }

        XCTAssertEqual(providers.count, 3)
        // Each promise carries a distinct entry path.
        let carried = providers.compactMap { $0.userInfo as? String }
        XCTAssertEqual(Set(carried).count, 3)
        XCTAssertEqual(Set(carried), Set(entries.map { $0.path }))
    }

    /// Step 1: the failure message singles out the (likely) encrypted / not-found case.
    func testExtractionFailureMessageForNotFound() {
        let text = ZipFilePromiseDelegate.informativeText(for: ZipReaderError.entryNotFound("x"))
        XCTAssertTrue(text.lowercased().contains("password-protected"))
    }

    // MARK: - Hostile size fields (regression for a footer/HTML arithmetic-overflow trap)

    private func huge(_ path: String) -> ZipEntryItem {
        ZipEntryItem(id: path, path: path, fileName: path, isDirectory: false,
                     uncompressedSize: .max, compressedSize: .max, modificationDate: nil)
    }

    func testImplausibleSizesExcludedFromTotal() {
        // Implausible (>1 PiB) sizes are treated as unreadable, not summed — so no crash
        // and no fabricated figure. A mix: one real (100 B) + one garbage (UInt64.max).
        let real = ZipEntryItem(id: "r", path: "r", fileName: "r", isDirectory: false,
                                uncompressedSize: 100, compressedSize: 100, modificationDate: nil)
        let entries = [real, huge("g")]
        XCTAssertTrue(ZipEntryItem.hasUnreliableSizes(in: entries))
        XCTAssertFalse(real.isSizeReliable == false)
        XCTAssertFalse(huge("g").isSizeReliable)
        // Total counts only the reliable entry (garbage excluded), never Int64.max.
        XCTAssertEqual(ZipEntryItem.totalUncompressedByteCount(of: entries), 100)
    }

    func testFooterOmitsTotalWhenSizesUnreliable() {
        // Rendering a listing with absurd sizes must not crash, and must not show a total.
        let html = ZipListingHTML.render(for: [huge("a.bin"), huge("b.bin")], name: "evil.zip")
        XCTAssertTrue(html.contains("2 files"))
        XCTAssertTrue(html.contains("some sizes unavailable"))
        XCTAssertFalse(html.contains(" total"), "no fabricated total when sizes are garbage")
    }

    // MARK: - Preview size cap (zip-bomb DoS guard)

    func testPreviewSizeCap() {
        func md(_ size: UInt64) -> ZipEntryItem {
            ZipEntryItem(id: "x", path: "x", fileName: "x.md", isDirectory: false,
                         uncompressedSize: size, compressedSize: 1, modificationDate: nil)
        }
        XCTAssertTrue(InAppTextPreview.isPreviewable(md(1_000)))                // small → ok
        XCTAssertFalse(InAppTextPreview.isPreviewable(md(100 * 1024 * 1024)))   // 100 MB → refused
        XCTAssertFalse(InAppTextPreview.isPreviewable(huge("g")))              // unreadable size → refused
    }
}
