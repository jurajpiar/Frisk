import Foundation

/// A single entry within a zip archive, described from the central directory alone
/// (no inflation of the entry's data). Shared by the app window and the Quick Look
/// extension.
struct ArchiveEntryItem: Identifiable, Hashable {
    let id: String          // entry path inside the archive
    let path: String        // same as id; full path within archive
    let fileName: String    // last path component
    let isDirectory: Bool
    let uncompressedSize: UInt64
    let compressedSize: UInt64
    let modificationDate: Date?
}

extension ArchiveEntryItem {
    /// Sizes at/above this are treated as unreadable rather than real. No single file in a
    /// hand-handled archive is a petabyte; values this large come from a corrupt/hostile
    /// central directory or a library mis-parse (e.g. ZIPFoundation returns garbage
    /// uncompressed sizes for some macOS-created Zip64 archives). We refuse to display or
    /// sum these rather than fabricate an absurd figure (e.g. "9.22 EB").
    static let implausibleSizeThreshold: UInt64 = 1 << 50   // 1 PiB (~1.13 PB)

    /// Whether this entry's reported uncompressed size is plausible enough to show.
    var isSizeReliable: Bool { uncompressedSize < Self.implausibleSizeThreshold }

    /// This entry's uncompressed size clamped to `Int64` for `ByteCountFormatter`.
    var displayByteCount: Int64 { Int64(min(uncompressedSize, UInt64(Int64.max))) }

    /// Overflow-safe total of the *reliably-sized* file entries (directories and
    /// implausible sizes excluded), clamped to `Int64.max`.
    static func totalUncompressedByteCount(of entries: [ArchiveEntryItem]) -> Int64 {
        var total: UInt64 = 0
        for entry in entries where !entry.isDirectory && entry.isSizeReliable {
            let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            total = overflow ? .max : sum
        }
        return Int64(min(total, UInt64(Int64.max)))
    }

    /// True if any file entry has an implausible (unreadable) size — the total can't be
    /// trusted and should be omitted rather than shown wrong.
    static func hasUnreliableSizes(in entries: [ArchiveEntryItem]) -> Bool {
        entries.contains { !$0.isDirectory && !$0.isSizeReliable }
    }
}
