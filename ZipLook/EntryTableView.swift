import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Quartz   // QLPreviewPanel for in-app Quick Look

/// AppKit `NSTableView` (in an `NSScrollView`) wrapped for SwiftUI (D5). Shows the entry
/// listing and, via the same `Coordinator`, drags a row out as a file promise (D6).
struct EntryTableView: NSViewRepresentable {
    let entries: [ZipEntryItem]
    let archiveURL: URL

    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let size = NSUserInterfaceItemIdentifier("size")
        static let modified = NSUserInterfaceItemIdentifier("modified")
    }

    func makeCoordinator() -> Coordinator { Coordinator(entries: entries, archiveURL: archiveURL) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = QuickLookTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowSizeStyle = .default
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.doubleAction = #selector(Coordinator.tableDoubleClicked(_:))
        table.target = context.coordinator

        let nameCol = NSTableColumn(identifier: Column.name)
        nameCol.title = "Name"
        nameCol.width = 300
        nameCol.minWidth = 160

        let sizeCol = NSTableColumn(identifier: Column.size)
        sizeCol.title = "Size"
        sizeCol.width = 90
        sizeCol.minWidth = 70

        let modCol = NSTableColumn(identifier: Column.modified)
        modCol.title = "Modified"
        modCol.width = 160
        modCol.minWidth = 120

        table.addTableColumn(nameCol)
        table.addTableColumn(sizeCol)
        table.addTableColumn(modCol)

        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        context.coordinator.tableView = table

        // In-app Quick Look: spacebar previews the selected entry (extracted on demand).
        let ql = context.coordinator.quickLookController
        ql.tableView = table
        ql.selectionProvider = { [weak table, weak coordinator = context.coordinator] in
            guard let table, let coordinator else { return [] }
            return table.selectedRowIndexes.map { coordinator.entries[$0] }
        }
        table.quickLookController = ql

        // Allow dragging rows out to other apps (Finder) as a copy (D6).
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(entries: entries, archiveURL: archiveURL)
        (nsView.documentView as? NSTableView)?.reloadData()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var entries: [ZipEntryItem]
        private(set) var archiveURL: URL
        /// Rebuilt whenever the open archive changes so promises extract from the right file.
        private(set) var promiseDelegate: ZipFilePromiseDelegate
        /// Drives the in-app Quick Look panel; rebuilt when the open archive changes.
        private(set) var quickLookController: QuickLookController
        weak var tableView: NSTableView?

        private let byteFormatter: ByteCountFormatter = {
            let f = ByteCountFormatter()
            f.countStyle = .file
            return f
        }()

        private let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return f
        }()

        init(entries: [ZipEntryItem], archiveURL: URL) {
            self.entries = entries
            self.archiveURL = archiveURL
            self.promiseDelegate = ZipFilePromiseDelegate(archiveURL: archiveURL)
            self.quickLookController = QuickLookController(archiveURL: archiveURL)
        }

        func update(entries: [ZipEntryItem], archiveURL: URL) {
            self.entries = entries
            if archiveURL != self.archiveURL {
                self.archiveURL = archiveURL
                self.promiseDelegate = ZipFilePromiseDelegate(archiveURL: archiveURL)
                quickLookController.cleanup()
                quickLookController = QuickLookController(archiveURL: archiveURL)
                rewireQuickLook()
            }
        }

        /// Re-point the Quick Look controller at the (unchanged) table after a rebuild.
        private func rewireQuickLook() {
            guard let table = tableView as? QuickLookTableView else { return }
            quickLookController.tableView = table
            quickLookController.selectionProvider = { [weak table, weak self] in
                guard let table, let self else { return [] }
                return table.selectedRowIndexes.map { self.entries[$0] }
            }
            table.quickLookController = quickLookController
        }

        /// Double-clicking a row previews it, matching Finder's behaviour.
        @objc func tableDoubleClicked(_ sender: Any?) {
            (tableView as? QuickLookTableView)?.toggleQuickLook()
        }

        /// Keep an open preview in sync as the selection changes (live-follow), switching
        /// between the in-app markdown window and the system panel as the type dictates.
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = tableView as? QuickLookTableView, table.anyPreviewVisible() else { return }
            quickLookController.refreshFromSelection()
            table.previewSelection()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

        /// Provide a file promise for a dragged row. Directories are not draggable in
        /// v1 (returns nil). Nothing is extracted here — only on drop.
        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            let item = entries[row]
            guard !item.isDirectory else { return nil }
            let ext = (item.fileName as NSString).pathExtension
            let fileType = UTType(filenameExtension: ext) ?? .data
            let provider = NSFilePromiseProvider(fileType: fileType.identifier,
                                                 delegate: promiseDelegate)
            provider.userInfo = item.path   // carry the entry path to the delegate
            return provider
        }

        func tableView(_ tableView: NSTableView,
                       viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let item = entries[row]

            let text: String
            let monospaced: Bool
            switch tableColumn.identifier {
            case Column.name:
                // Full path (trailing slash kept for directories) so a flat listing is
                // unambiguous and comparable with `unzip -l`.
                text = item.path
                monospaced = false
            case Column.size:
                text = (item.isDirectory || !item.isSizeReliable) ? "\u{2014}"
                    : byteFormatter.string(fromByteCount: item.displayByteCount)
                monospaced = true
            case Column.modified:
                text = item.modificationDate.map(dateFormatter.string(from:)) ?? "\u{2014}"
                monospaced = false
            default:
                text = ""
                monospaced = false
            }

            let cell = reusableCell(for: tableColumn.identifier, in: tableView)
            cell.textField?.stringValue = text
            cell.textField?.font = monospaced
                ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : .systemFont(ofSize: NSFont.systemFontSize)
            // Directories are greyed to signal they are not draggable (v1 files-only, D5/stage 04).
            cell.textField?.textColor = item.isDirectory ? .secondaryLabelColor : .labelColor
            return cell
        }

        /// Reuse (or build) a simple text cell for a column.
        private func reusableCell(for id: NSUserInterfaceItemIdentifier,
                                  in tableView: NSTableView) -> NSTableCellView {
            if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
                return reused
            }
            let cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

/// `NSTableView` that toggles the shared Quick Look panel on spacebar and routes the
/// panel's data source/delegate to the `QuickLookController` (Finder-style preview).
final class QuickLookTableView: NSTableView {
    weak var quickLookController: QuickLookController?

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggleQuickLook()
        } else {
            super.keyDown(with: event)
        }
    }

    /// Spacebar: toggle. If any preview is showing, close it; otherwise preview the
    /// current selection with the appropriate previewer.
    func toggleQuickLook() {
        if anyPreviewVisible() { closeAllPreviews() } else { previewSelection() }
    }

    func anyPreviewVisible() -> Bool {
        InAppTextPreview.shared.isVisible
            || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true)
    }

    func closeAllPreviews() {
        InAppTextPreview.shared.close()
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared()?.orderOut(nil) }
    }

    /// A single markdown entry renders in our in-app window (the system panel's Markdown
    /// previewer can't read our sandbox temp); everything else uses the system panel.
    /// Switches previewer as the selection changes so the two never fight.
    func previewSelection() {
        guard let controller = quickLookController else { return }
        controller.refreshFromSelection()
        let files = controller.selectedFiles()
        if files.count == 1, let entry = files.first, InAppTextPreview.isMarkdown(entry) {
            if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared()?.orderOut(nil) }
            if let url = controller.extractedURL(for: entry),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                InAppTextPreview.shared.show(title: entry.fileName, markdown: content,
                                             fileURL: url, navigationTable: self)
            } else {
                NSSound.beep()
            }
        } else if controller.hasPreviewableSelection {
            InAppTextPreview.shared.close()
            guard let panel = QLPreviewPanel.shared() else { return }
            if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        } else {
            NSSound.beep()   // nothing previewable (e.g. a directory)
        }
    }

    // MARK: - QLPreviewPanelController (responder-chain informal protocol)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        quickLookController?.refreshFromSelection()
        panel.dataSource = quickLookController
        panel.delegate = quickLookController
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
