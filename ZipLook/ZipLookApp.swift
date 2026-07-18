import SwiftUI

/// Application entry point. SwiftUI lifecycle (D1): opening a zip shows its entries in an
/// in-app table; entries drag out to Finder and preview in-app (spacebar). A separate
/// Quick Look preview extension handles glancing at a zip in Finder.
@main
struct ZipLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ArchiveStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in store.open(url) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") { store.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About ZipLook") { AppDelegate.showAboutPanel() }
            }
        }
    }
}

/// Handles `open` Apple Events (double-click / Open With -> ZipLook in Finder).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            ArchiveStore.shared.open(url)
        }
    }

    /// Standard About panel with a credits section stating the ZIPFoundation MIT licence.
    @MainActor
    static func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: "A tiny viewer for peeking inside zip archives and dragging single "
                  + "entries out to Finder.\n\n"
                  + "Zip reading by ZIPFoundation (MIT Licence)\n"
                  + "© 2017–2025 Thomas Zoechling and the ZIP Foundation project authors.\n"
                  + "https://github.com/weichsel/ZIPFoundation\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor
            ]
        )
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
