import Foundation
import AppKit
import FileProvider
import UniformTypeIdentifiers

/// App-side manager for File Provider domains: opens a zip, creates a security-scoped
/// bookmark, stores it in the shared App Group, registers a domain, and reveals it in
/// Finder. One domain per opened zip.
@MainActor
final class DomainManager: ObservableObject {
    static let shared = DomainManager()

    struct Mount: Identifiable, Hashable {
        let id: String          // domain identifier
        let displayName: String
    }

    @Published private(set) var mounts: [Mount] = []
    @Published var lastMessage: String?

    private init() { refresh() }

    /// List the actually-registered domains (source of truth), so orphaned/stale domains
    /// are visible and removable — not just those in our store.
    func refresh() {
        NSFileProviderManager.getDomainsWithCompletionHandler { [weak self] domains, _ in
            let list = domains
                .map { Mount(id: $0.identifier.rawValue, displayName: $0.displayName) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            Task { @MainActor in self?.mounts = list }
        }
    }

    /// Present an open panel and mount the chosen zip.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Mount"
        if panel.runModal() == .OK, let url = panel.url {
            mount(url)
        }
    }

    /// Create a security-scoped bookmark of `url`, register a domain for it, reveal it.
    func mount(_ url: URL) {
        // Diagnostics: does the app have read access to the panel URL at all?
        let started = url.startAccessingSecurityScopedResource()
        let readBytes = (try? Data(contentsOf: url).count) ?? -1
        NSLog("ZLFP mount probe: started=\(started) readBytes=\(readBytes) url=\(url.path)")
        do {
            // Read-only scope to match the user-selected.read-only entitlement; the default
            // (read-write) scope needs the read-write entitlement and fails with Cocoa 256.
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            if started { url.stopAccessingSecurityScopedResource() }
            let domainID = "zip-" + UUID().uuidString
            let displayName = url.lastPathComponent
            ZipDomainStore.set(bookmark: bookmark, displayName: displayName, forDomainID: domainID)
            let domain = NSFileProviderDomain(identifier: .init(domainID), displayName: displayName)
            NSFileProviderManager.add(domain) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.lastMessage = "Could not mount \(displayName): \(error.localizedDescription)"
                        ZipDomainStore.remove(domainID: domainID)
                    } else {
                        self?.lastMessage = "Mounted \(displayName)"
                        self?.reveal(domainID: domainID)
                    }
                    self?.refresh()
                }
            }
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            let ns = error as NSError
            lastMessage = "Bookmark failed (started=\(started), read=\(readBytes)B): \(ns.domain) \(ns.code)"
        }
    }

    /// Open the domain's Finder location.
    func reveal(domainID: String) {
        let displayName = ZipDomainStore.displayName(forDomainID: domainID) ?? ""
        let domain = NSFileProviderDomain(identifier: .init(domainID), displayName: displayName)
        guard let manager = NSFileProviderManager(for: domain) else { return }
        manager.getUserVisibleURL(for: .rootContainer) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                let didAccess = url.startAccessingSecurityScopedResource()
                NSWorkspace.shared.activateFileViewerSelecting([url])
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
        }
    }

    /// Unmount and forget a domain.
    func remove(domainID: String) {
        let displayName = ZipDomainStore.displayName(forDomainID: domainID) ?? ""
        let domain = NSFileProviderDomain(identifier: .init(domainID), displayName: displayName)
        NSFileProviderManager.remove(domain) { [weak self] _ in
            ZipDomainStore.remove(domainID: domainID)
            Task { @MainActor in
                self?.lastMessage = "Removed \(displayName)"
                self?.refresh()
            }
        }
    }
}
