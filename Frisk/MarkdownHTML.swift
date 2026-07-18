import Foundation
import Markdown

/// Renders Markdown to HTML by walking Apple's swift-markdown AST. Every text value is
/// HTML-escaped (raw inline/block HTML from the document is escaped, not passed through),
/// so the output is safe to display in a WebView. Fenced ```mermaid blocks become
/// `<pre class="mermaid">` so mermaid.js can render them.
enum MarkdownHTML {
    static func render(_ markdown: String) -> String {
        let document = Document(parsing: markdown)
        var emitter = HTMLEmitter()
        return emitter.visit(document)
    }

    static func escape(_ s: String) -> String {
        var o = s
        o = o.replacingOccurrences(of: "&", with: "&amp;")
        o = o.replacingOccurrences(of: "<", with: "&lt;")
        o = o.replacingOccurrences(of: ">", with: "&gt;")
        o = o.replacingOccurrences(of: "\"", with: "&quot;")
        return o
    }
}

private struct HTMLEmitter: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // Inline
    mutating func visitText(_ text: Text) -> String { MarkdownHTML.escape(text.string) }
    mutating func visitEmphasis(_ node: Emphasis) -> String { "<em>\(defaultVisit(node))</em>" }
    mutating func visitStrong(_ node: Strong) -> String { "<strong>\(defaultVisit(node))</strong>" }
    mutating func visitStrikethrough(_ node: Strikethrough) -> String { "<del>\(defaultVisit(node))</del>" }
    mutating func visitInlineCode(_ node: InlineCode) -> String { "<code>\(MarkdownHTML.escape(node.code))</code>" }
    mutating func visitLineBreak(_ node: LineBreak) -> String { "<br>\n" }
    mutating func visitSoftBreak(_ node: SoftBreak) -> String { "\n" }
    mutating func visitInlineHTML(_ node: InlineHTML) -> String { MarkdownHTML.escape(node.rawHTML) }

    mutating func visitLink(_ node: Link) -> String {
        "<a href=\"\(MarkdownHTML.escape(node.destination ?? ""))\">\(defaultVisit(node))</a>"
    }
    mutating func visitImage(_ node: Image) -> String {
        "<img src=\"\(MarkdownHTML.escape(node.source ?? ""))\" alt=\"\(MarkdownHTML.escape(node.plainText))\">"
    }

    // Blocks
    mutating func visitParagraph(_ node: Paragraph) -> String { "<p>\(defaultVisit(node))</p>\n" }
    mutating func visitHeading(_ node: Heading) -> String {
        let level = min(max(node.level, 1), 6)
        return "<h\(level)>\(defaultVisit(node))</h\(level)>\n"
    }
    mutating func visitThematicBreak(_ node: ThematicBreak) -> String { "<hr>\n" }
    mutating func visitBlockQuote(_ node: BlockQuote) -> String { "<blockquote>\n\(defaultVisit(node))</blockquote>\n" }
    mutating func visitHTMLBlock(_ node: HTMLBlock) -> String { "<pre>\(MarkdownHTML.escape(node.rawHTML))</pre>\n" }

    mutating func visitCodeBlock(_ node: CodeBlock) -> String {
        let language = (node.language ?? "").lowercased()
        if language == "mermaid" {
            return "<pre class=\"mermaid\">\(MarkdownHTML.escape(node.code))</pre>\n"
        }
        let cls = language.isEmpty ? "" : " class=\"language-\(MarkdownHTML.escape(language))\""
        return "<pre><code\(cls)>\(MarkdownHTML.escape(node.code))</code></pre>\n"
    }

    mutating func visitUnorderedList(_ node: UnorderedList) -> String { "<ul>\n\(defaultVisit(node))</ul>\n" }
    mutating func visitOrderedList(_ node: OrderedList) -> String { "<ol>\n\(defaultVisit(node))</ol>\n" }
    mutating func visitListItem(_ node: ListItem) -> String {
        if let checkbox = node.checkbox {
            let checked = checkbox == .checked ? " checked" : ""
            return "<li><input type=\"checkbox\" disabled\(checked)> \(defaultVisit(node))</li>\n"
        }
        return "<li>\(defaultVisit(node))</li>\n"
    }

    // GFM tables
    mutating func visitTable(_ node: Markdown.Table) -> String {
        var html = "<table>\n"
        let headCells = node.head.children.compactMap { $0 as? Markdown.Table.Cell }
        if !headCells.isEmpty {
            html += "<thead><tr>" + headCells.map { "<th>\(cellHTML($0))</th>" }.joined() + "</tr></thead>\n"
        }
        let rows = node.body.children.compactMap { $0 as? Markdown.Table.Row }
        html += "<tbody>\n"
        for row in rows {
            let cells = row.children.compactMap { $0 as? Markdown.Table.Cell }
            html += "<tr>" + cells.map { "<td>\(cellHTML($0))</td>" }.joined() + "</tr>\n"
        }
        html += "</tbody></table>\n"
        return html
    }

    private mutating func cellHTML(_ cell: Markdown.Table.Cell) -> String {
        cell.children.map { visit($0) }.joined()
    }
}
