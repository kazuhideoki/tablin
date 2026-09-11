import AppKit

@main struct AppKitTests {
  static func main() throws {
    _ = NSApplication.shared
    let document = TablinDocument()
    document.model = TableModel(matrix: [["H1", "H2"], ["a", "b"], ["c", "d"]])
    document.model.showsRowNumbers = false
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
    // Legacy scrollers must not consume the single-line editing viewport.
    controller.beginEditing()
    let input = controller.editor!
    let inputScroll = input.enclosingScrollView!
    inputScroll.scrollerStyle = .legacy
    input.insertText(String(repeating: "日本語入力", count: 30), replacementRange: input.selectedRange())
    input.sizeToFit()
    inputScroll.tile()
    input.scrollRangeToVisible(NSRange(location: (input.string as NSString).length, length: 0))
    let lineHeight = input.layoutManager!.defaultLineHeight(for: input.font!)
    print("Editing viewport: \(inputScroll.contentSize.height), line: \(lineHeight)")
    precondition(inputScroll.contentSize.height >= lineHeight + 2 * input.textContainerInset.height)
    precondition(input.visibleRect.maxX >= input.frame.width - 1)
    controller.cancelEditing()
    print("PASS single-line editor keeps text visible and scrolls to long input with legacy style")
    undo.beginUndoGrouping()
    controller.toggleWrap(nil)
    controller.toggleRowNumbers(nil)
    controller.zoomIn(nil)
    controller.alignRight(nil)
    undo.endUndoGrouping()
    precondition(
      document.model.wraps && document.model.showsRowNumbers && document.model.fontSize == 13)
    precondition(controller.table.numberOfColumns == document.model.columns.count + 1)
    undo.undo()
    precondition(!document.model.wraps && !document.model.showsRowNumbers)
    print("PASS wrapping / row numbers / zoom / alignment and undo")
    controller.scroll.magnification = 1
    controller.window?.contentView?.layoutSubtreeIfNeeded()
    let beforeZoom = document.model
    let wasEdited = document.isDocumentEdited
    let cellFrame = controller.table.frameOfCell(atColumn: 0, row: 1)
    let originalSize = controller.table.convert(cellFrame, to: nil).size
    controller.beginEditing()
    let zoomEditor = controller.editor!
    let editorSize = zoomEditor.convert(zoomEditor.bounds, to: nil).size
    controller.zoomIn(nil)
    let enlargedSize = controller.table.convert(cellFrame, to: nil).size
    precondition(abs(enlargedSize.width / originalSize.width - 1.1) < 0.001)
    precondition(abs(enlargedSize.height / originalSize.height - 1.1) < 0.001)
    precondition(controller.editor === zoomEditor)
    precondition(
      abs(zoomEditor.convert(zoomEditor.bounds, to: nil).width / editorSize.width - 1.1) < 0.001)
    let center = controller.table.convert(
      NSPoint(x: cellFrame.midX, y: cellFrame.midY), to: nil)
    let hit = controller.table.convert(center, from: nil)
    precondition(controller.table.row(at: hit) == 1 && controller.table.column(at: hit) == 0)
    controller.zoomOut(nil)
    precondition(abs(controller.scroll.magnification - 1) < 0.001)
    for _ in 0..<40 { controller.zoomOut(nil) }
    precondition(controller.scroll.magnification == 0.5)
    for _ in 0..<40 { controller.zoomIn(nil) }
    precondition(controller.scroll.magnification == 3)
    precondition(document.model == beforeZoom && document.isDocumentEdited == wasEdited)
    controller.cancelEditing()
    controller.reload()
    precondition(controller.scroll.magnification == 3)
    controller.scroll.magnification = 1
    print("PASS whole-table zoom / editor scaling / hit testing / limits without document changes")
    let zoomDocument = TablinDocument()
    zoomDocument.model = TableModel(
      matrix: (0..<80).map { row in
        (0..<16).map { "\(row):\($0)" }
      })
    zoomDocument.makeWindowControllers()
    let zoomController = zoomDocument.tableController!
    zoomController.window?.contentView?.layoutSubtreeIfNeeded()
    for showsNumbers in [false, true] {
      zoomDocument.model.showsRowNumbers = showsNumbers
      zoomController.reload()
      for editing in [false, true] {
        zoomController.scroll.magnification = 1
        zoomController.select(row: 60, column: 12)
        if editing { zoomController.beginEditing() }
        let activeEditor = zoomController.editor
        for _ in 0..<20 {
          zoomController.zoomIn(nil)
          let focused = zoomController.table.frameOfCell(
            atColumn: 12 + zoomController.columnOffset, row: 60)
          precondition(zoomController.table.visibleRect.insetBy(dx: -1, dy: -1).contains(focused))
          precondition(zoomController.selectedRow == 60 && zoomController.selectedColumn == 12)
          precondition(zoomController.editor === activeEditor)
        }
        if editing { zoomController.cancelEditing() }
      }
    }
    zoomController.close()
    print("PASS zoom keeps distant focused cell visible with row numbers and during editing")
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
    try checkAutomaticGrowth()
    try checkRichText()
    checkControlNavigation()
    checkCommandReturn()
    checkDeletionShortcuts()
    checkSearch()
    checkSearchVisibilityAndFocus()
    document.close()
    print("25 AppKit checks passed")
  }

  static func checkSearchVisibilityAndFocus() {
    let document = TablinDocument()
    document.model = TableModel(matrix: [
      ["Header"], [String(repeating: "long text ", count: 100) + "needle"],
    ])
    document.model.columns[0].width = 100
    document.makeWindowControllers()
    defer { document.close() }
    let controller = document.tableController!
    controller.window!.contentView!.layoutSubtreeIfNeeded()
    controller.showSearch(nil)
    func query(_ value: String) {
      controller.searchField.stringValue = value
      controller.controlTextDidChange(
        Notification(
          name: NSControl.textDidChangeNotification,
          object: controller.searchField))
    }
    for wraps in [false, true] {
      document.model.wraps = wraps
      controller.reload()
      query("needle")
      let overlay = controller.searchOverlay!
      controller.table.layoutSubtreeIfNeeded()
      precondition(controller.table.subviews.last === overlay)
      precondition(
        overlay.text.visibleRect.contains(overlay.matchRect),
        "wraps=\(wraps) visible=\(overlay.text.visibleRect) match=\(overlay.matchRect) textFrame=\(overlay.text.frame) overlay=\(overlay.frame)"
      )
      precondition(
        controller.table.visibleRect.contains(
          overlay.text.convert(overlay.matchRect, to: controller.table)))
      precondition(overlay.hitTest(.zero) == nil)
      for _ in 0..<5 {
        controller.zoomIn(nil)
        precondition(
          controller.table.visibleRect.insetBy(dx: -1, dy: -1).contains(
            overlay.text.convert(overlay.matchRect, to: controller.table)))
      }
      controller.scroll.magnification = 1
      if wraps {
        precondition(overlay.text.visibleRect.minY > 0)
      } else {
        precondition(overlay.text.visibleRect.minX > 0)
      }
    }
    controller.beginEditing()
    precondition(controller.searchOverlay == nil)
    controller.editor!.string = "needle needle"
    controller.window!.makeFirstResponder(controller.searchField)
    let searchInput = controller.window!.firstResponder!
    controller.controlTextDidBeginEditing(
      Notification(
        name: NSControl.textDidBeginEditingNotification,
        object: controller.searchField))
    precondition(controller.editor == nil)
    precondition(document.model.rows[1].cells[0] == "needle needle")
    precondition(controller.window!.firstResponder === searchInput)
    precondition(controller.searchMatches.count == 2)
    controller.findNext(nil)
    controller.findNext(nil)
    precondition(controller.searchIndex == 0 && controller.window!.firstResponder === searchInput)
    controller.beginEditing()
    controller.editor!.string = "needle"
    controller.closeSearch(nil)
    precondition(controller.editor == nil && controller.searchOverlay == nil)
    precondition(document.model.rows[1].cells[0] == "needle")
    print(
      "PASS clipped and tall matches are visible / passive viewport / return to find preserves focus / Done commits edit"
    )
  }

  static func checkSearch() {
    let document = TablinDocument()
    document.model = TableModel(matrix: [["Cat", "日本語"], ["🐈 cat CAT", "日本語 日本語"]])
    document.makeWindowControllers()
    defer { document.close() }
    let controller = document.tableController!
    let original = document.model
    controller.showSearch(nil)
    func query(_ value: String) {
      controller.searchField.stringValue = value
      controller.controlTextDidChange(
        Notification(
          name: NSControl.textDidChangeNotification,
          object: controller.searchField))
    }
    query("cat")
    precondition(controller.searchMatches.count == 3 && controller.searchIndex == 0)
    precondition(controller.selectedRow == 0)
    controller.findNext(nil)
    precondition(controller.selectedRow == 1 && controller.searchMatches[1].range.location == 3)
    controller.findNext(nil)
    precondition(controller.searchIndex == 2)
    let column = controller.table.tableColumns[controller.columnOffset]
    let cell = controller.tableView(controller.table, viewFor: column, row: 1) as! NSTableCellView
    let value = cell.textField!.attributedStringValue
    precondition(
      value.attribute(.backgroundColor, at: 3, effectiveRange: nil) as? NSColor == .systemYellow)
    precondition(
      value.attribute(.backgroundColor, at: 7, effectiveRange: nil) as? NSColor == .systemOrange)
    controller.findNext(nil)
    precondition(controller.searchIndex == 0)
    controller.findPrevious(nil)
    precondition(controller.searchIndex == 2)
    query("日本語")
    precondition(controller.searchMatches.count == 3)
    let input = NSTextView()
    input.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(
      !controller.control(
        controller.searchField, textView: input,
        doCommandBy: #selector(NSResponder.insertNewline(_:))))
    input.unmarkText()
    precondition(
      controller.control(
        controller.searchField, textView: input,
        doCommandBy: #selector(NSResponder.insertNewline(_:))))
    precondition(controller.searchIndex == 1)
    query("missing")
    controller.findNext(nil)
    precondition(controller.searchCount.stringValue == "0件")
    query("")
    precondition(controller.searchMatches.isEmpty)
    precondition(document.model == original && !document.isDocumentEdited)
    query("cat")
    controller.closeSearch(nil)
    precondition(
      controller.searchMatches.isEmpty && controller.window!.firstResponder === controller.table)
    controller.select(row: 1, column: 0)
    controller.beginEditing()
    controller.editor!.string = "cat cat cat"
    controller.showSearch(nil)
    precondition(controller.editor == nil && controller.searchMatches.count == 4)
    document.undoManager!.undo()
    precondition(controller.searchMatches.count == 3)
    print(
      "PASS search ordering / Unicode ranges / highlights / wraparound / IME / no matches / nonmutating search / edit and undo"
    )
  }

  static func checkDeletionShortcuts() {
    let document = TablinDocument()
    document.model = TableModel(matrix: [["A", "B"], ["a", "b"], ["c", "d"]])
    document.makeWindowControllers()
    defer { document.close() }
    let controller = document.tableController!
    let undo = document.undoManager!
    undo.groupsByEvent = false
    let original = document.model
    func event(_ flags: NSEvent.ModifierFlags) -> NSEvent {
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil,
        characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
    }
    for flags: NSEvent.ModifierFlags in [.option, [.option, .shift], []] {
      controller.select(row: 2, column: 1)
      undo.beginUndoGrouping()
      controller.table.keyDown(with: event(flags))
      undo.endUndoGrouping()
      if flags == .option {
        precondition(document.model.rows.count == 2 && document.model.columns.count == 2)
        precondition(controller.selectedRow == 1 && controller.selectedColumn == 1)
      } else if flags.contains(.shift) {
        precondition(document.model.rows.count == 3 && document.model.columns.count == 1)
        precondition(controller.selectedRow == 2 && controller.selectedColumn == 0)
      } else {
        precondition(document.model.rows.count == 3 && document.model.columns.count == 2)
        precondition(document.model.rows[2].cells[1].isEmpty)
      }
      precondition(controller.window!.firstResponder === controller.table)
      undo.undo()
      precondition(document.model == original)
    }
    controller.select(row: 0, column: 0)
    undo.beginUndoGrouping()
    controller.table.keyDown(with: event(.option))
    precondition(document.model == original)
    controller.table.keyDown(with: event([.option, .shift]))
    let singleColumn = document.model
    controller.table.keyDown(with: event([.option, .shift]))
    precondition(document.model == singleColumn)
    undo.endUndoGrouping()
    undo.undo()
    for flags: NSEvent.ModifierFlags in [.option, [.option, .shift]] {
      controller.select(row: 1, column: 0)
      controller.beginEditing()
      let editor = controller.editor!
      editor.string = "hello world"
      editor.setSelectedRange(NSRange(location: 11, length: 0))
      editor.keyDown(with: event(flags))
      precondition(controller.editor === editor && document.model == original)
      if flags == .option { precondition(editor.string == "hello ") }
      controller.cancelEditing()
    }
    print("PASS deletion shortcuts / selection / undo / protected edges / text editing")
  }

  static func checkCommandReturn() {
    let document = TablinDocument()
    document.model = TableModel(matrix: [["A", "B"], ["a", "b"]])
    document.makeWindowControllers()
    defer { document.close() }
    let controller = document.tableController!
    document.undoManager!.groupsByEvent = false
    document.undoManager!.beginUndoGrouping()
    defer { document.undoManager!.endUndoGrouping() }
    for keyCode: UInt16 in [36, 76] {
      controller.select(row: 1, column: 1)
      controller.beginEditing()
      controller.editor!.string = "確定した値"
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil,
        characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
      controller.editor!.keyDown(with: event)
      precondition(document.model.rows[1].cells[1] == "確定した値")
      precondition(controller.selectedRow == 1 && controller.selectedColumn == 2)
      precondition(controller.editor == nil)
      precondition(controller.window!.firstResponder === controller.table)
      controller.table.keyDown(with: event)
      precondition(controller.selectedRow == 1 && controller.selectedColumn == 3)
      precondition(controller.editor == nil)
      precondition(document.model.rows[1].cells[1] == "確定した値")
      let plainReturn = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil,
        characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
      controller.table.keyDown(with: plainReturn)
      precondition(controller.selectedRow == 2 && controller.selectedColumn == 3)
    }
    print(
      "PASS Command Return / keypad Enter moves right while editing or selected; Return moves down")
  }

  static func checkControlNavigation() {
    let document = TablinDocument()
    document.model = TableModel(matrix: [["A", "B", "C"], ["a", "b", "c"], ["d", "e", "f"]])
    document.makeWindowControllers()
    defer { document.close() }
    let controller = document.tableController!
    let original = document.model
    func press(_ letter: String, shift: Bool = false) {
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: shift ? [.control, .shift] : [.control],
        timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil,
        characters: letter, charactersIgnoringModifiers: letter, isARepeat: false, keyCode: 0)!
      controller.table.keyDown(with: event)
    }
    controller.select(row: 1, column: 1)
    for (letter, row, column) in [("f", 1, 2), ("b", 1, 1), ("n", 2, 1), ("p", 1, 1)] {
      press(letter)
      precondition(controller.selectedRow == row && controller.selectedColumn == column)
      precondition(controller.editor == nil)
    }
    press("F", shift: true)
    press("N", shift: true)
    precondition(controller.selection.rows == 1...2 && controller.selection.columns == 1...2)
    controller.select(row: 0, column: 0)
    press("b")
    press("p")
    precondition(controller.selectedRow == 0 && controller.selectedColumn == 0)
    precondition(document.model == original)
    print("PASS Control F/B/N/P navigation / Shift selection / top-left boundary")
  }

  static func checkAutomaticGrowth() throws {
    let document = TablinDocument()
    document.model = TableModel(matrix: [["Header", ""], ["", ""]])
    document.makeWindowControllers()
    let controller = document.tableController!
    let undo = document.undoManager!
    undo.groupsByEvent = false
    defer { document.close() }
    let original = document.model
    undo.beginUndoGrouping()
    controller.select(row: 1, column: 1)
    controller.move(dx: 0, dy: 1)
    precondition(document.model.rows.count == 3)
    controller.move(dx: 0, dy: -1)
    precondition(document.model == original && controller.selectedRow == 1)
    controller.move(dx: 1, dy: 0)
    precondition(document.model.columns.count == 3)
    controller.move(dx: -1, dy: 0)
    precondition(document.model == original && controller.selectedColumn == 1)
    undo.endUndoGrouping()
    print("PASS unused automatic rows and columns disappear; existing empty edges survive")

    undo.beginUndoGrouping()
    controller.move(dx: 1, dy: 1)
    controller.move(dx: 1, dy: 1)
    controller.select(row: 1, column: 1)
    precondition(document.model == original)
    undo.endUndoGrouping()
    undo.undo()
    undo.redo()
    precondition(document.model == original)
    _ = try document.model.validated()
    print("PASS multiple unused edges disappear on mouse selection with undo / redo")

    undo.beginUndoGrouping()
    controller.select(row: 1, column: 1)
    controller.move(dx: 1, dy: 0)
    controller.move(dx: -1, dy: 0, extend: true)
    precondition(document.model.columns.count == 3)
    precondition(controller.selection.columns == 1...2)
    controller.select(row: 1, column: 1)
    precondition(document.model == original)
    undo.endUndoGrouping()
    print("PASS automatic edges remain while included in the selection")

    undo.beginUndoGrouping()
    controller.move(dx: 0, dy: 1)
    controller.beginEditing()
    controller.editor!.string = "日本語"
    controller.move(dx: 0, dy: -1)
    precondition(document.model.rows.count == 3)
    precondition(document.model.rows[2].cells[1] == "日本語")
    controller.select(row: 2, column: 1)
    controller.clearCells(nil)
    controller.move(dx: 0, dy: -1)
    precondition(document.model.rows.count == 3)
    controller.move(dx: 1, dy: 0)
    controller.beginEditing()
    controller.editor!.string = " "
    controller.move(dx: -1, dy: 0)
    precondition(document.model.columns.count == 3)
    undo.endUndoGrouping()
    print("PASS committed content and whitespace keep automatic edges even after clearing")

    undo.beginUndoGrouping()
    controller.select(row: 2, column: 2)
    controller.move(dx: 0, dy: 1)
    controller.beginEditing()
    controller.editor!.string = "cancelled"
    controller.cancelEditing()
    controller.move(dx: 0, dy: -1)
    precondition(document.model.rows.count == 3)
    controller.move(dx: 1, dy: 0)
    controller.beginEditing()
    controller.move(dx: -1, dy: 0)
    precondition(document.model.columns.count == 3)
    undo.endUndoGrouping()
    print("PASS cancelled and empty edits do not keep automatic edges")

    undo.beginUndoGrouping()
    controller.rowEnd(nil)
    controller.columnEnd(nil)
    controller.select(row: 1, column: 0)
    precondition(document.model.rows.count == 4 && document.model.columns.count == 4)
    let saved = try JSONDecoder().decode(TableModel.self, from: document.data(ofType: tablinType))
    precondition(saved == document.model)
    undo.endUndoGrouping()
    print("PASS explicitly appended empty rows and columns remain and serialize")

    let labelsDocument = TablinDocument()
    labelsDocument.model = TableModel(matrix: [Array(repeating: "heading", count: 28)])
    labelsDocument.makeWindowControllers()
    let labels = labelsDocument.tableController!
    let beforeLabels = labelsDocument.model
    precondition(labels.table.headerView != nil)
    precondition(!labels.table.allowsColumnReordering)
    precondition(labels.table.tableColumns[0].title.isEmpty)
    precondition(labels.table.tableColumns[1].title == "A")
    precondition(labels.table.tableColumns[26].title == "Z")
    precondition(labels.table.tableColumns[27].title == "AA")
    precondition(labels.table.tableColumns[28].title == "AB")
    precondition(labelsDocument.model == beforeLabels)
    labels.window?.contentView?.layoutSubtreeIfNeeded()
    func checkHeaderGeometry() {
      let header = labels.table.headerView!
      precondition(header.visibleRect.height > 0)
      for column in labels.table.tableColumns.indices {
        let headerRect = header.convert(header.headerRect(ofColumn: column), to: nil)
        let cellRect = labels.table.convert(labels.table.rect(ofColumn: column), to: nil)
        precondition(abs(headerRect.minX - cellRect.minX) < 1)
        precondition(abs(headerRect.width - cellRect.width) < 1)
      }
    }
    for scale: CGFloat in [0.5, 1.1, 2, 3] {
      labels.scroll.magnification = scale
      for column in [0, 14, 28, 0] {
        labels.table.scrollColumnToVisible(column)
        checkHeaderGeometry()
      }
      for width: CGFloat in [640, 1060] {
        labels.window?.setContentSize(NSSize(width: width, height: 640))
        labels.window?.contentView?.layoutSubtreeIfNeeded()
        checkHeaderGeometry()
      }
    }
    let linkedColumn = labelsDocument.model.columns[0].id
    labelsDocument.model.insertColumn(at: 0)
    labelsDocument.model.showsRowNumbers = false
    labels.reload()
    labels.window?.contentView?.layoutSubtreeIfNeeded()
    checkHeaderGeometry()
    precondition(labels.table.tableColumns[0].title == "A")
    precondition(labels.table.tableColumns[1].title == "B")
    precondition(labels.table.tableColumns[1].identifier.rawValue == linkedColumn.uuidString)
    precondition(labelsDocument.model.rows[0].cells[1] == "heading")
    print(
      "PASS column labels / Z-AA boundary / row-number offset / stable identity after insertion")

  }

  static func checkRichText() throws {
    let richDoc = TablinDocument()
    richDoc.model = TableModel(matrix: [["Header", "Other"], ["Hello 日本語 👋", "plain"]])
    richDoc.makeWindowControllers()
    let rich = richDoc.tableController!
    rich.select(row: 1, column: 0)
    rich.beginEditing()
    rich.editor!.setSelectedRange(NSRange(location: 6, length: 3))
    for bit in [1, 2, 4] { rich.toggleStyle(bit) }
    let richDraft = rich.modelForSaving()
    precondition(richDraft.rows[1].formats?[0]?.first?.style == 7)
    precondition(richDraft.rows[1].formats?[0]?.first?.location == 6)
    precondition(richDraft.rows[1].formats?[0]?.first?.length == 3)
    _ = try richDraft.validated()
    rich.finishEditing()
    let richData = try richDoc.data(ofType: tablinType)
    let richRestored = try JSONDecoder().decode(TableModel.self, from: richData).validated()
    precondition(richRestored == richDoc.model)
    let clipboard =
      NSPasteboard.general.pasteboardItems?.map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
      } ?? []
    defer {
      NSPasteboard.general.clearContents()
      let items = clipboard.map { values in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
      }
      NSPasteboard.general.writeObjects(items)
    }
    rich.copy(nil)
    rich.select(row: 1, column: 1)
    rich.paste(nil)
    precondition(richDoc.model.rows[1].formats?[1] == richDoc.model.rows[1].formats?[0])
    rich.beginEditing()
    rich.editor!.setSelectedRange(NSRange(location: 0, length: 5))
    rich.toggleStyle(1)
    rich.cancelEditing()
    precondition(richDoc.model.rows[1].formats?[1] == richRestored.rows[1].formats?[0])
    rich.select(row: 1, column: 0)
    rich.select(row: 1, column: 1, extend: true)
    let richUndo = richDoc.undoManager!
    while richUndo.groupingLevel > 0 { richUndo.endUndoGrouping() }
    richUndo.removeAllActions()
    richUndo.groupsByEvent = false
    richUndo.beginUndoGrouping()
    rich.toggleStyle(4)
    richUndo.endUndoGrouping()
    for c in 0...1 {
      rich.attributedCell(row: 1, column: c).enumerateAttributes(
        in: NSRange(location: 0, length: rich.attributedCell(row: 1, column: c).length)
      ) { a, _, _ in
        precondition(TableWindowController.style(a) & 4 != 0)
      }
    }
    richUndo.undo()
    precondition(richDoc.model.rows[1].formats?[0] == richRestored.rows[1].formats?[0])
    var shifted = richDoc.model
    shifted.insertColumn(at: 0)
    precondition(shifted.rows[1].formats?[1] == richRestored.rows[1].formats?[0])
    shifted.removeColumn(at: 0)
    precondition(shifted == richDoc.model)
    var invalidRuns = richDoc.model
    invalidRuns.rows[1].formats?[0] = [TextRun(location: 0, length: Int.max, style: 1)]
    precondition((try? invalidRuns.validated()) == nil)
    print(
      "PASS rich text ranges / combined styles / persistence / copy / cancel / multi-cell undo / column shift / validation"
    )

    // Merely visiting any cell must preserve implicit formatting and dirty state.
    let untouched = TablinDocument()
    untouched.model = TableModel(matrix: [["Header", ""], ["body", ""]])
    untouched.makeWindowControllers()
    let visiting = untouched.tableController!
    let originalModel = untouched.model
    for r in 0...1 {
      for c in 0...1 {
        visiting.select(row: r, column: c)
        visiting.beginEditing()
        precondition(visiting.modelForSaving() == originalModel)
        visiting.finishEditing()
        visiting.beginEditing()
        visiting.cancelEditing()
        precondition(untouched.model == originalModel && !untouched.isDocumentEdited)
        precondition(untouched.undoManager?.canUndo == false)
      }
    }
    visiting.select(row: 0, column: 0)
    visiting.copy(nil)
    visiting.paste(nil)
    precondition(
      TableWindowController.style(
        visiting.attributedCell(row: 0, column: 0).attributes(at: 0, effectiveRange: nil)) == 1)
    visiting.select(row: 1, column: 0)
    visiting.paste(nil)
    precondition(
      TableWindowController.style(
        visiting.attributedCell(row: 1, column: 0).attributes(at: 0, effectiveRange: nil)) == 1)
    // Empty cells retain pending formatting and participate in toggling it off.
    visiting.select(row: 1, column: 1, extend: true)
    for bit in [1, 2, 4] {
      visiting.toggleStyle(bit)
      visiting.toggleStyle(bit)
      precondition(
        TableWindowController.style(
          visiting.attributedCell(row: 1, column: 0).attributes(at: 0, effectiveRange: nil)) & bit
          == 0)
      precondition(untouched.model.rows[1].formats?[1] == [])
    }
    visiting.select(row: 1, column: 1)
    visiting.toggleStyle(4)
    _ = try untouched.model.validated()
    let emptyRoundTrip = try JSONDecoder().decode(
      TableModel.self, from: untouched.data(ofType: tablinType))
    precondition(emptyRoundTrip.rows[1].formats?[1]?.first?.style == 4)
    visiting.beginEditing()
    visiting.editor!.insertText("new", replacementRange: visiting.editor!.selectedRange())
    precondition(visiting.modelForSaving().rows[1].formats?[1]?.first?.style == 4)
    visiting.finishEditing()
    // Search highlights and the passive current-match viewport keep the same formatting.
    visiting.searchField.stringValue = "new"
    visiting.showSearch(nil)
    precondition(visiting.searchOverlay != nil)
    precondition(
      TableWindowController.style(
        visiting.searchOverlay!.text.attributedString().attributes(at: 0, effectiveRange: nil)) == 4
    )
    visiting.toggleStyle(1)
    precondition(
      TableWindowController.style(
        visiting.searchOverlay!.text.attributedString().attributes(at: 0, effectiveRange: nil)) == 5
    )
    visiting.closeSearch(nil)
    visiting.beginEditing()
    let editing = visiting.editor!
    editing.setSelectedRange(NSRange(location: 0, length: 3))
    while editing.undoManager!.groupingLevel > 0 { editing.undoManager!.endUndoGrouping() }
    editing.undoManager!.removeAllActions()
    editing.undoManager!.groupsByEvent = false
    editing.undoManager!.beginUndoGrouping()
    visiting.toggleStyle(2)
    editing.undoManager!.endUndoGrouping()
    precondition(visiting.modelForSaving().rows[1].formats?[1]?.first?.style == 7)
    editing.undoManager!.undo()
    precondition(visiting.modelForSaving().rows[1].formats?[1]?.first?.style == 5)
    editing.undoManager!.beginUndoGrouping()
    editing.setMarkedText(
      "日本", selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: 0, length: 3))
    let marked = editing.attributedString().copy() as! NSAttributedString
    visiting.toggleStyle(1)
    precondition(editing.attributedString().isEqual(to: marked))
    editing.undoManager!.endUndoGrouping()
    visiting.cancelEditing()
    print(
      "PASS no-op edits / implicit header copy / empty cell formatting / search formatting / editor undo / IME"
    )

  }
}
