import SwiftUI

/// Minimal manager window: mount a zip (it appears in Finder), reveal or unmount existing
/// mounts. Browsing / Quick Look / drag-out all happen natively in Finder.
struct FileProviderManagerView: View {
    @ObservedObject private var manager = DomainManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("ZipLook").font(.title2).bold()
                    Text("Mount a zip to browse it in Finder — preview and drag entries out natively.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Mount Zip\u{2026}") { manager.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            Divider()

            if manager.mounts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No archives mounted").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(manager.mounts) { mount in
                    HStack {
                        Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                        Text(mount.displayName)
                        Spacer()
                        Button("Reveal") { manager.reveal(domainID: mount.id) }
                        Button("Unmount", role: .destructive) { manager.remove(domainID: mount.id) }
                    }
                }
            }

            if let message = manager.lastMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { manager.refresh() }
    }
}
