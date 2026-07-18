import Foundation

/// Supplies the file list and content for one File Provider domain. Swapping the backend
/// is how the extension goes from the M2 static tree to the M3 zip-backed tree.
protocol ProviderBackend {
    func rootName() -> String
    func files() -> [FPFile]
    /// Extract/produce the given entry to a temp file and return its URL.
    func extract(entryPath: String) throws -> URL
}

/// Diagnostic backend: surfaces *why* the zip backend couldn't be used as a filename in
/// the mount (since os_log isn't visible here). Temporary, for M3 debugging.
struct DiagnosticBackend: ProviderBackend {
    let reason: String
    func rootName() -> String { "Frisk DIAG" }
    func files() -> [FPFile] { [FPFile(path: "DIAG--\(reason).txt", size: Int64(reason.utf8.count))] }
    func extract(entryPath: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("diag.txt")
        try Data(reason.utf8).write(to: url)
        return url
    }
}

/// M2: a fixed tree used to prove enumeration + materialisation work end-to-end.
struct StaticBackend: ProviderBackend {
    func rootName() -> String { "Frisk Static" }

    func files() -> [FPFile] {
        [FPFile(path: "readme.txt", size: 14),
         FPFile(path: "docs/notes.md", size: 12),
         FPFile(path: "docs/deep/inner.txt", size: 6)]
    }

    func extract(entryPath: String) throws -> URL {
        let contents: [String: String] = [
            "readme.txt": "Hello Frisk\n",
            "docs/notes.md": "nested file\n",
            "docs/deep/inner.txt": "inner\n"
        ]
        let name = (entryPath as NSString).lastPathComponent
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data((contents[entryPath] ?? "").utf8).write(to: url)
        return url
    }
}
