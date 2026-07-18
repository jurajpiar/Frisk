import SwiftUI

/// Top-level window content. Switches between empty / loading / loaded / error states
/// driven by `ArchiveStore`.
struct ContentView: View {
    @EnvironmentObject private var store: ArchiveStore

    var body: some View {
        content
            .frame(minWidth: 520, minHeight: 360)
            .navigationTitle(store.archiveURL?.lastPathComponent ?? "ZipLook")
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .empty:
            placeholder
        case .loading:
            ProgressView("Reading archive…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let entries):
            if let url = store.archiveURL {
                loaded(entries, archiveURL: url)
            } else {
                placeholder
            }
        case .failed(let message):
            errorState(message)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a zip archive")
                .font(.title2)
            Text("Choose File \u{203A} Open\u{2026} (\u{2318}O), or open a .zip with ZipLook from Finder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open\u{2026}") { store.presentOpenPanel() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loaded(_ entries: [ZipEntryItem], archiveURL: URL) -> some View {
        VStack(spacing: 0) {
            EntryTableView(entries: entries, archiveURL: archiveURL)
            Divider()
            footer(for: entries)
        }
    }

    private func footer(for entries: [ZipEntryItem]) -> some View {
        let files = entries.filter { !$0.isDirectory }
        // Omit the total when any size is unreadable, rather than show a fabricated figure.
        let summary: String
        if ZipEntryItem.hasUnreliableSizes(in: entries) {
            summary = "\(files.count) files (some sizes unavailable)"
        } else {
            let totalText = ByteCountFormatter.string(
                fromByteCount: ZipEntryItem.totalUncompressedByteCount(of: entries), countStyle: .file)
            summary = "\(files.count) files, \(totalText) total"
        }
        return HStack {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Cannot read this archive")
                .font(.title2)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Open a different file\u{2026}") { store.presentOpenPanel() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
