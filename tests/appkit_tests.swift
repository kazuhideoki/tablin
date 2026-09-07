import AppKit

@main struct AppKitTests {
  static func main() throws {
    _ = NSApplication.shared
    let document = TablinDocument()
    document.model = TableModel(matrix: [["H1", "H2"], ["a", "b"], ["c", "d"]])
    document.makeWindowControllers()
    let controller = document.tableController!
    let undo = document.undoManager!
    undo.groupsByEvent = false
    controller.select(row: 2, column: 1)
    undo.beginUndoGrouping()
    controller.insertRow(above: true)
    controller.insertColumn(before: true)
    undo.endUndoGrouping()
    precondition(document.model.rows.count == 4 && document.model.columns.count == 3)
    undo.undo()
    precondition(document.model.rows.count == 3 && document.model.columns.count == 2)
    undo.redo()
    precondition(document.model.rows.count == 4 && document.model.columns.count == 3)
    print("PASS AppKit insert / undo / redo with stale row views")
    // Force view creation at the old row index as AppKit may do during column replacement.
    precondition(
      controller.tableView(controller.table, viewFor: controller.table.tableColumns[0], row: 99)
        == nil)
    print("PASS stale AppKit row callback is bounded")
    undo.beginUndoGrouping()
    controller.select(row: 1, column: 0)
    controller.removeRow(nil)
    controller.removeColumn(nil)
    undo.endUndoGrouping()
    undo.undo()
    _ = try document.model.validated()
    print("PASS remove row / column and restore")
    let data = try document.data(ofType: tablinType)
    let restored = TablinDocument()
    try restored.read(from: data, ofType: tablinType)
    precondition(restored.model == document.model)
    print("PASS NSDocument serialization")
    // Window stays offscreen; test the editor/document contract without synthesizing events.
    undo.beginUndoGrouping()
    controller.select(row: 1, column: 0)
    let original = document.model.rows[1].cells[0]
    controller.beginEditing()
    let editor = controller.editor!
    editor.string = "日本語\n編集途中"
    let draft = try JSONDecoder().decode(TableModel.self, from: document.data(ofType: tablinType))
    precondition(draft.rows[1].cells[0] == editor.string)
    precondition(controller.editor === editor)
    precondition(document.model.rows[1].cells[0] == original)
    controller.cancelEditing()
    let cancelled = try JSONDecoder().decode(
      TableModel.self, from: document.data(ofType: tablinType))
    precondition(cancelled.rows[1].cells[0] == original)
    undo.endUndoGrouping()
    print("PASS saving draft keeps editor alive; cancel restores original")
    undo.beginUndoGrouping()
    controller.toggleWrap(nil)
    controller.toggleRowNumbers(nil)
    controller.zoomIn(nil)
    controller.alignRight(nil)
    undo.endUndoGrouping()
    precondition(
      document.model.wraps && document.model.showsRowNumbers && document.model.fontSize == 14)
    precondition(controller.table.numberOfColumns == document.model.columns.count + 1)
    undo.undo()
    precondition(!document.model.wraps && !document.model.showsRowNumbers)
    print("PASS wrapping / row numbers / zoom / alignment and undo")
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "tablin_bookmark_" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: root)
      UserDefaults.standard.removeObject(forKey: "document." + document.model.id.uuidString)
    }
    let originalFile = root.appendingPathComponent("original.tablin")
    let movedFile = root.appendingPathComponent("移動 & # 済み.tablin")
    try document.data(ofType: tablinType).write(to: originalFile)
    DocumentLocations.remember(document.model.id, url: originalFile)
    let link = try CellLink(document.model.link(file: originalFile, row: 1, column: 0))
    try FileManager.default.moveItem(at: originalFile, to: movedFile)
    precondition(
      DocumentLocations.locate(link).standardizedFileURL == movedFile.standardizedFileURL)
    print("PASS bookmark resolves a moved and renamed document")
    undo.beginUndoGrouping()
    controller.beginEditing()
    controller.editor!.setMarkedText(
      "にほんご", selectedRange: NSRange(location: 4, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(controller.editor!.hasMarkedText())
    precondition(
      !controller.textView(
        controller.editor!, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    precondition(controller.editor != nil)
    controller.cancelEditing()
    undo.endUndoGrouping()
    print("PASS marked Japanese text is not intercepted as cell navigation")
    document.model.wraps = true
    document.model.rows[1].cells[0] = String(repeating: "日本語の文章です。", count: 8)
    document.model.columns[0].width = 100
    controller.reload()
    let narrowHeight = controller.tableView(controller.table, heightOfRow: 1)
    undo.beginUndoGrouping()
    controller.table.tableColumns[0].width = 500
    controller.columnResized(Notification(name: NSTableView.columnDidResizeNotification))
    undo.endUndoGrouping()
    let wideHeight = controller.tableView(controller.table, heightOfRow: 1)
    precondition(wideHeight < narrowHeight)
    precondition(document.model.columns[0].width == 500)
    print("PASS column resizing recalculates wrapped row height")
    document.close()
    print("9 AppKit checks passed")
  }
}
