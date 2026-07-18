import XCTest
@testable import Frisk

/// Stage 05: the HTML listing must escape attacker-controlled entry names and cap rows.
final class PreviewHTMLTests: XCTestCase {

    private func item(_ path: String, size: UInt64 = 10, dir: Bool = false) -> ZipEntryItem {
        ZipEntryItem(id: path, path: path,
                     fileName: (path as NSString).lastPathComponent,
                     isDirectory: dir, uncompressedSize: size, compressedSize: size,
                     modificationDate: nil)
    }

    func testEscapesScriptAndAmpersandInNames() {
        let entries = [item("<script>alert('x')</script>.txt"), item("a&b.txt")]
        let html = ZipListingHTML.render(for: entries, name: "evil.zip")

        // The literal tag must not appear as markup.
        XCTAssertFalse(html.contains("<script>"), "unescaped <script> is an injection")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("a&amp;b.txt"))
    }

    func testPreservesUnicodeNames() {
        let entries = [item("résumé-üé.txt")]
        let html = ZipListingHTML.render(for: entries, name: "cv.zip")
        XCTAssertTrue(html.contains("résumé-üé.txt"), "unicode should pass through unmangled")
    }

    func testEscapesArchiveNameInHeader() {
        let html = ZipListingHTML.render(for: [item("ok.txt")], name: "<b>name</b>.zip")
        XCTAssertFalse(html.contains("<b>name</b>.zip"))
        XCTAssertTrue(html.contains("&lt;b&gt;name&lt;/b&gt;.zip"))
    }

    func testCapsRowsWithSummary() {
        let count = ZipListingHTML.rowCap + 500
        let entries = (0..<count).map { item("file-\($0).txt") }
        let html = ZipListingHTML.render(for: entries, name: "many.zip")

        let renderedRows = html.components(separatedBy: "<td class=\"name\">").count - 1
        XCTAssertEqual(renderedRows, ZipListingHTML.rowCap, "should render exactly the cap")
        XCTAssertTrue(html.contains("and 500 more"))
    }

    func testValidDocumentStructure() {
        let html = ZipListingHTML.render(for: [item("a.txt"), item("d/", dir: true)], name: "s.zip")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("1 files"))   // directory excluded from file count
    }
}
