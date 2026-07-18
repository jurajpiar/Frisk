import Foundation
import QuickLook
import QuickLookUI
import UniformTypeIdentifiers

/// Data-based Quick Look preview (D3): reads an archive's directory and returns an
/// HTML listing. Read-only — no extraction, no interaction (D4). HTML is produced by
/// the shared `ZipListingHTML` renderer in ZipCore.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let reader = ArchiveReaders.reader(for: request.fileURL)
        // On failure, rethrow so the system falls back to the default icon preview
        // (step 5). Do not render an error page.
        let entries = try reader.listEntries()
        let html = ZipListingHTML.render(for: entries, name: request.fileURL.lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html,
                              contentSize: CGSize(width: 620, height: 480)) { _ in
            Data(html.utf8)
        }
    }
}
