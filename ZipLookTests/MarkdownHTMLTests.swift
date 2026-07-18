import XCTest
@testable import ZipLook

/// The swift-markdown → HTML emitter: rich constructs render, mermaid blocks are tagged
/// for mermaid.js, and text is HTML-escaped (no injection).
final class MarkdownHTMLTests: XCTestCase {

    func testHeadingsEmphasisAndInlineCode() {
        let html = MarkdownHTML.render("# Title\n\nsome **bold** and `code` here")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testGFMTableRendersAsHTMLTable() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = MarkdownHTML.render(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>A</th>"))
        XCTAssertTrue(html.contains("<td>1</td>"))
    }

    func testMermaidFenceTaggedForMermaid() {
        let md = "```mermaid\nflowchart TD\nA-->B\n```"
        let html = MarkdownHTML.render(md)
        XCTAssertTrue(html.contains("<pre class=\"mermaid\">"), "mermaid blocks must be tagged for mermaid.js")
        XCTAssertTrue(html.contains("flowchart TD"))
    }

    func testPlainCodeBlockIsNotMermaid() {
        let html = MarkdownHTML.render("```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"))
        XCTAssertFalse(html.contains("class=\"mermaid\""))
    }

    func testEscapesHTMLInText() {
        let html = MarkdownHTML.render("a <script>alert(1)</script> & <b>x</b>")
        XCTAssertFalse(html.contains("<script>"), "raw HTML must be escaped, not passed through")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&amp;"))
    }
}
