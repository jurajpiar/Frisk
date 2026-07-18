import Foundation

/// Encodes a file path into a File Provider domain identifier (hex, always
/// identifier-safe) and back. Used so the extension can locate its zip directly from
/// `domain.identifier` without a shared-store lookup (avoids an init-time read race).
enum DomainIDCodec {
    private static let prefix = "zippath-"

    static func encode(path: String) -> String {
        prefix + Data(path.utf8).map { String(format: "%02x", $0) }.joined()
    }

    static func decodePath(_ identifier: String) -> String? {
        guard identifier.hasPrefix(prefix) else { return nil }
        let hex = identifier.dropFirst(prefix.count)
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            bytes.append(b); i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
