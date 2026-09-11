import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
  let documents = TablinDocumentController()
  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(receiveURL(_:reply:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    buildMenus()
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
  }
  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  @objc func receiveURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
    guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: string)
    else { return }
    openCell(url)
  }
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.scheme == tablinURLScheme {
        openCell(url)
      } else {
        documents.openDocument(withContentsOf: url, display: true) { _, _, error in
          if let error { NSApp.presentError(error) }
        }
      }
    }
  }
  func openCell(_ url: URL) {
    do {
      let link = try CellLink(url)
      if let document = documents.documents.compactMap({ $0 as? TablinDocument }).first(where: {
        $0.model.id == link.document
      }) {
        try reveal(link, in: document)
        return
      }
      let location = DocumentLocations.locate(link)
      // Validate identity before adding an unrelated document to the application.
      let model = try JSONDecoder().decode(TableModel.self, from: Data(contentsOf: location))
        .validated()
      _ = try model.position(for: link)
      documents.openDocument(withContentsOf: location, display: true) {
        [weak self] document, _, error in
        if let error {
          NSApp.presentError(error)
          return
        }
        guard let document = document as? TablinDocument else { return }
        do { try self?.reveal(link, in: document) } catch { NSApp.presentError(error) }
      }
    } catch { NSApp.presentError(error) }
  }
  private func reveal(_ link: CellLink, in document: TablinDocument) throws {
    let position = try document.model.position(for: link)
    if document.windowControllers.isEmpty { document.makeWindowControllers() }
    document.showWindows()
    document.tableController?.select(row: position.row, column: position.column)
    document.tableController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func importTable(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [
      .commaSeparatedText, .tabSeparatedText, UTType(filenameExtension: "md") ?? .plainText,
      .plainText,
    ]
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url, let self else { return }
      do {
        let text = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()
        let matrix =
          ext == "md"
          ? try TableText.parseMarkdown(text)
          : try TableText.parseDelimited(text, separator: ext == "csv" ? "," : "\t")
        self.newDocument(matrix: matrix)
      } catch { NSApp.presentError(error) }
    }
  }
  @objc func newFromClipboard(_ sender: Any?) {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    do { newDocument(matrix: try TableText.parseDelimited(text, separator: "\t")) } catch {
      NSApp.presentError(error)
    }
  }
  private func newDocument(matrix: [[String]]) {
    let doc = TablinDocument()
    doc.model = TableModel(matrix: matrix)
    documents.addDocument(doc)
    doc.makeWindowControllers()
    doc.showWindows()
    doc.updateChangeCount(.changeDone)
  }
  private func buildMenus() {
    let main = NSMenu()
    NSApp.mainMenu = main
    func menu(_ title: String) -> NSMenu {
      let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
      let submenu = NSMenu(title: title)
      item.submenu = submenu
      return submenu
    }
    func item(
      _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
      _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil
    ) {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = target
    }
    let app = menu("Tablin")
    item(app, "About Tablin", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    app.addItem(.separator())
    item(app, "Hide Tablin", #selector(NSApplication.hide(_:)), "h")
    item(
      app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
      [.command, .option])
    item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
    app.addItem(.separator())
    item(app, "Quit Tablin", #selector(NSApplication.terminate(_:)), "q")
    let file = menu("File")
    item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n", target: documents)
    item(
      file, "New from Clipboard", #selector(newFromClipboard(_:)), "n", [.command, .option],
      target: self)
    item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o", target: documents)
    item(
      file, "Import CSV / TSV / Markdown…", #selector(importTable(_:)), "i", [.command, .shift],
      target: self)
    file.addItem(.separator())
    item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
    item(file, "Save…", #selector(NSDocument.save(_:)), "s")
    item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
    file.addItem(.separator())
    item(file, "Export CSV…", #selector(TableWindowController.exportCSV(_:)))
    item(file, "Export Markdown…", #selector(TableWindowController.exportMarkdown(_:)))
    let edit = menu("Edit")
    item(edit, "Undo", Selector(("undo:")), "z")
    item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
    edit.addItem(.separator())
    item(edit, "Cut", #selector(NSText.cut(_:)), "x")
    item(edit, "Copy", #selector(NSText.copy(_:)), "c")
    item(edit, "Paste", #selector(NSText.paste(_:)), "v")
    item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
    edit.addItem(.separator())
    item(edit, "Edit Cell", #selector(TableWindowController.editCell(_:)))
    item(edit, "Clear Cells", #selector(TableWindowController.clearCells(_:)))
    item(
      edit, "Copy Link to Cell", #selector(TableWindowController.copyCellLink(_:)), "c",
      [.command, .option])
    item(
      edit, "Copy Table as Markdown", #selector(TableWindowController.copyMarkdown(_:)), "c",
      [.command, .shift])
    item(edit, "Copy Table as CSV", #selector(TableWindowController.copyCSV(_:)))
    let table = menu("Table")
    item(table, "Insert Column Before", #selector(TableWindowController.columnBefore(_:)))
    item(table, "Insert Column After", #selector(TableWindowController.columnAfter(_:)))
    item(table, "Append Column", #selector(TableWindowController.columnEnd(_:)))
    item(table, "Remove Column", #selector(TableWindowController.removeColumn(_:)))
    table.addItem(.separator())
    item(table, "Insert Row Above", #selector(TableWindowController.rowAbove(_:)))
    item(table, "Insert Row Below", #selector(TableWindowController.rowBelow(_:)))
    item(table, "Append Row", #selector(TableWindowController.rowEnd(_:)))
    item(table, "Remove Row", #selector(TableWindowController.removeRow(_:)))
    table.addItem(.separator())
    item(
      table, "Align Left", #selector(TableWindowController.alignLeft(_:)), "[", [.command, .shift])
    item(
      table, "Align Center", #selector(TableWindowController.alignCenter(_:)), "\\",
      [.command, .shift])
    item(
      table, "Align Right", #selector(TableWindowController.alignRight(_:)), "]",
      [.command, .shift])
    item(table, "Prune Empty Edges", #selector(TableWindowController.prune(_:)))
    let view = menu("View")
    item(view, "Row Numbers", #selector(TableWindowController.toggleRowNumbers(_:)))
    item(
      view, "Wrap Cell Text", #selector(TableWindowController.toggleWrap(_:)), "w",
      [.command, .option])
    view.addItem(.separator())
    item(view, "Zoom In", #selector(TableWindowController.zoomIn(_:)), "+")
    item(view, "Zoom Out", #selector(TableWindowController.zoomOut(_:)), "-")
    let window = menu("Window")
    NSApp.windowsMenu = window
    item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
    item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
    item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
  }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
