import SwiftUI
import AppKit
import WebKit

/// In-app preview for **Markdown** entries only. Markdown's Quick Look previewer (a
/// third-party extension) can't read our sandbox temp, so the system panel fails for it —
/// we render it ourselves in a `WKWebView`: swift-markdown → HTML, with bundled mermaid.js
/// (offline) drawing ```mermaid diagrams. All other types keep using the system panel.
@MainActor
final class InAppTextPreview {
    static let shared = InAppTextPreview()
    private var window: NSWindow?
    private weak var navigationTable: NSTableView?
    private var keyMonitor: Any?

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "markdn", "mkd"]

    /// Largest markdown entry we'll extract + render in-app. Bigger (or unreadable-size)
    /// entries are refused rather than extracted, to avoid a zip-bomb DoS on spacebar.
    static let previewByteCap: UInt64 = 20 * 1024 * 1024   // 20 MB

    static func isMarkdown(_ entry: ArchiveEntryItem) -> Bool {
        markdownExtensions.contains((entry.fileName as NSString).pathExtension.lowercased())
    }

    /// Safe to extract + preview: a plausibly-sized, not-too-large entry.
    static func isPreviewable(_ entry: ArchiveEntryItem) -> Bool {
        entry.isSizeReliable && entry.uncompressedSize <= previewByteCap
    }

    var isVisible: Bool { window?.isVisible == true }
    func close() { window?.close() }

    /// Show (or update) the preview for a markdown entry. `fileURL` is the extracted temp
    /// file (for the "Open with…" button); `navigationTable` receives forwarded arrow keys
    /// so entries can be navigated like the system Quick Look panel.
    func show(title: String, markdown content: String, fileURL: URL?, navigationTable: NSTableView?) {
        self.navigationTable = navigationTable
        installKeyMonitorIfNeeded()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = title
        window?.contentView = NSHostingView(rootView: MarkdownPreviewView(markdown: content, fileURL: fileURL))
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Intercept keys while this window is key so spacebar/escape dismiss and arrows
    /// navigate the table (rather than scrolling the web view).
    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, NSApp.keyWindow === self.window else { return event }
            switch event.keyCode {
            case 49, 53:                       // space, escape → dismiss
                self.close(); return nil
            case 125, 126, 115, 119:           // down, up, home, end → navigate the table
                self.navigationTable?.keyDown(with: event); return nil
            default:
                return event
            }
        }
    }
}

private struct MarkdownPreviewView: View {
    let markdown: String
    let fileURL: URL?   // nil when the entry was refused (too large / unreadable size)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if let fileURL {
                    Button(openTitle(fileURL)) { NSWorkspace.shared.open(fileURL) }
                }
            }
            .padding(8)
            Divider()
            MarkdownWebView(bodyHTML: MarkdownHTML.render(markdown))
        }
        .frame(minWidth: 520, minHeight: 360)
    }

    /// "Open with <DefaultApp>", matching the system Quick Look panel.
    private func openTitle(_ url: URL) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) {
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            return "Open with \(name)"
        }
        return "Open"
    }
}

/// WKWebView that renders a fully self-contained HTML document (styles + emitted body +
/// inlined mermaid.js) via loadHTMLString. Everything is inlined so nothing is loaded from
/// file:// — which the sandboxed WebContent process can't reliably read.
private struct MarkdownWebView: NSViewRepresentable {
    let bodyHTML: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(bodyHTML, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(bodyHTML, into: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastLoaded: String?
        private var ruleAdded = false
        private static var cachedRule: WKContentRuleList?

        func load(_ body: String, into webView: WKWebView) {
            guard body != lastLoaded else { return }   // avoid redundant reloads
            lastLoaded = body
            // Block ALL network in the preview before rendering: untrusted markdown must not
            // fetch remote images/trackers (the app has network.client only so WKWebView runs).
            ensureBlockingRule(on: webView) { [weak self] in
                webView.loadHTMLString(MarkdownDocument.html(body: body), baseURL: nil)
                _ = self
            }
        }

        private func ensureBlockingRule(on webView: WKWebView, then: @escaping () -> Void) {
            if ruleAdded { then(); return }
            let add: (WKContentRuleList) -> Void = { rule in
                webView.configuration.userContentController.add(rule)
                self.ruleAdded = true
                then()
            }
            if let rule = Self.cachedRule { add(rule); return }
            // Block remote (http/https) loads only — inline/local/data content still renders.
            let json = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
            guard let store = WKContentRuleListStore.default() else { then(); return }
            store.compileContentRuleList(forIdentifier: "frisk-block-all",
                                         encodedContentRuleList: json) { list, _ in
                if let list { Self.cachedRule = list; add(list) } else { then() }
            }
        }

        // Open link clicks in the default browser; block any in-preview navigation.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)                    // our own loadHTMLString
            } else {
                if let url = navigationAction.request.url,
                   let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            }
        }
    }
}

/// Builds the self-contained HTML document for the preview.
private enum MarkdownDocument {
    /// mermaid.min.js read once from the bundle and inlined.
    private static let mermaidJS: String = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    static func html(body: String) -> String {
        """
        <!doctype html><html lang="en-GB"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1"><style>\(css)</style></head>
        <body><article id="content">\(body)</article>
        <script>\(mermaidJS)</script>
        <script>
        (function () {
          try {
            var dark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
            if (window.mermaid) {
              window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
              window.mermaid.run({ querySelector: 'pre.mermaid' });
            }
          } catch (e) { /* leave mermaid blocks as text */ }
        })();
        </script></body></html>
        """
    }

    private static let css = """
      :root { color-scheme: light dark; }
      html, body { margin: 0; padding: 0; }
      body { font: 14px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
             color: #1d1d1f; background: #ffffff; padding: 20px 24px; }
      @media (prefers-color-scheme: dark) {
        body { color: #e8e8ea; background: #1e1e1e; }
        a { color: #6bb3ff; } tr:nth-child(even) { background: rgba(255,255,255,0.03); }
        th, td { border-color: #3a3a3c; } pre, code { background: rgba(255,255,255,0.06); }
        blockquote { color: #a1a1a6; border-color: #3a3a3c; } hr { border-color: #3a3a3c; }
      }
      #content { max-width: 820px; margin: 0 auto; }
      h1,h2,h3,h4 { line-height: 1.25; margin: 1.2em 0 .5em; }
      h1 { font-size: 1.9em; } h2 { font-size: 1.5em; border-bottom: 1px solid rgba(128,128,128,.25); padding-bottom:.2em; }
      h3 { font-size: 1.25em; } h4 { font-size: 1.05em; }
      p { margin: .6em 0; } a { color: #06c; text-decoration: none; } a:hover { text-decoration: underline; }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em;
             background: rgba(128,128,128,.12); padding: .15em .4em; border-radius: 4px; }
      pre { background: rgba(128,128,128,.10); padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
      pre code { background: none; padding: 0; } pre.mermaid { background: none; text-align: center; }
      blockquote { margin: .8em 0; padding: 0 1em; color: #6e6e73; border-left: 3px solid rgba(128,128,128,.4); }
      table { border-collapse: collapse; margin: .8em 0; width: 100%; }
      th, td { border: 1px solid rgba(128,128,128,.3); padding: 6px 10px; text-align: left; }
      tr:nth-child(even) { background: rgba(0,0,0,.03); }
      img { max-width: 100%; } hr { border: none; border-top: 1px solid rgba(128,128,128,.3); margin: 1.4em 0; }
      ul, ol { padding-left: 1.5em; }
    """
}
