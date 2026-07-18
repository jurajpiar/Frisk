import Foundation

/// Renders a zip entry listing as a self-contained HTML document for the Quick Look
/// preview (D3). Lives in ZipCore so it is shared by the extension and unit-tested by
/// the app's test target. Entry names are attacker-controlled, so every displayed
/// string is HTML-escaped.
enum ZipListingHTML {

    /// Maximum rows rendered; anything beyond gets a single summary row.
    static let rowCap = 1000

    static func render(for entries: [ZipEntryItem], name: String) -> String {
        let byteFormatter = ByteCountFormatter()
        byteFormatter.countStyle = .file

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let files = entries.filter { !$0.isDirectory }
        let summary: String
        if ZipEntryItem.hasUnreliableSizes(in: entries) {
            summary = "\(files.count) files (some sizes unavailable)"
        } else {
            let totalText = byteFormatter.string(fromByteCount: ZipEntryItem.totalUncompressedByteCount(of: entries))
            summary = "\(files.count) files, \(totalText) total"
        }

        var rows = ""
        for entry in entries.prefix(rowCap) {
            let sizeText = (entry.isDirectory || !entry.isSizeReliable) ? "&mdash;"
                : escape(byteFormatter.string(fromByteCount: entry.displayByteCount))
            let dateText = entry.modificationDate.map { escape(dateFormatter.string(from: $0)) } ?? "&mdash;"
            let rowClass = entry.isDirectory ? " class=\"dir\"" : ""
            rows += """
            <tr\(rowClass)><td class="name">\(escape(entry.path))</td>\
            <td class="size">\(sizeText)</td>\
            <td class="date">\(dateText)</td></tr>
            """
        }
        if entries.count > rowCap {
            let more = entries.count - rowCap
            rows += "<tr class=\"more\"><td colspan=\"3\">&hellip; and \(more) more</td></tr>"
        }

        return """
        <!DOCTYPE html>
        <html lang="en-GB">
        <head>
        <meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body { font: 13px -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; margin: 0; padding: 0; }
          header { padding: 12px 16px; border-bottom: 1px solid rgba(128,128,128,0.3); }
          header h1 { font-size: 14px; margin: 0; font-weight: 600; }
          header p { margin: 2px 0 0; color: gray; font-size: 12px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; padding: 4px 16px; border-bottom: 1px solid rgba(128,128,128,0.15);
                   white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          th { position: sticky; top: 0; background: rgba(128,128,128,0.12); font-weight: 600; font-size: 12px; }
          td.size, td.date { font-variant-numeric: tabular-nums; color: #444; }
          @media (prefers-color-scheme: dark) { td.size, td.date { color: #bbb; } }
          tr.dir td.name { color: gray; }
          tr.more td { color: gray; font-style: italic; }
        </style>
        </head>
        <body>
        <header>
          <h1>\(escape(name))</h1>
          <p>\(escape(summary))</p>
        </header>
        <table>
          <thead><tr><th>Name</th><th>Size</th><th>Modified</th></tr></thead>
          <tbody>
          \(rows)
          </tbody>
        </table>
        </body>
        </html>
        """
    }

    /// Minimal HTML-entity escaping for text content.
    static func escape(_ string: String) -> String {
        var out = string
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        out = out.replacingOccurrences(of: "'", with: "&#39;")
        return out
    }
}
