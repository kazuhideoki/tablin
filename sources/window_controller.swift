import AppKit
import UniformTypeIdentifiers

final class TableWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
  NSTextViewDelegate, NSToolbarDelegate, NSMenuItemValidation
{
  let doc: TablinDocument
  let table = GridTableView()
  let scroll = NSScrollView()
  let status = NSTextField(labelWithString: "")
  var editor: CellTextView?
  private var editorScroll: NSScrollView?
  var selectedRow = 1, selectedColumn = 0
  private var anchorRow = 1, anchorColumn = 0
  private var editRow = 0, editColumn = 0
  private var resizing = false
  private var rowHeights: [Int: CGFloat] = [:]
  private var pendingLinkCell: (row: UUID, column: UUID)?
  private var automaticRows: Set<UUID> = []
  private var automaticColumns: Set<UUID> = []
  var columnOffset: Int { doc.model.showsRowNumbers ? 1 : 0 }
  var selection: (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
    (
      min(anchorRow, selectedRow)...max(anchorRow, selectedRow),
      min(anchorColumn, selectedColumn)...max(anchorColumn, selectedColumn)
    )
  }
  init(document: TablinDocument) {
    doc = document
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1060, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.minSize = NSSize(width: 640, height: 320)
    window.title = "Untitled"
    window.toolbarStyle = .expanded
    super.init(window: window)
    window.center()
    let toolbar = NSToolbar(identifier: "Tablin.Toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    toolbar.sizeMode = .small
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    let content = NSView()
    window.contentView = content
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.allowsMagnification = true
    scroll.minMagnification = 0.5
    scroll.maxMagnification = 3
    content.addSubview(scroll)
    table.owner = self
    table.dataSource = self
    table.delegate = self
    table.headerView = nil
    table.selectionHighlightStyle = .none
    table.usesAutomaticRowHeights = false
    table.gridStyleMask = []
    table.gridColor = .separatorColor
    table.backgroundColor = .textBackgroundColor
    table.usesAlternatingRowBackgroundColors = false
    table.intercellSpacing = NSSize(width: 1, height: 1)
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.style = .plain
    scroll.documentView = table
    status.translatesAutoresizingMaskIntoConstraints = false
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    content.addSubview(status)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: content.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
      status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
      status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
      status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
      status.heightAnchor.constraint(equalToConstant: 15),
    ])
    NotificationCenter.default.addObserver(
      self, selector: #selector(columnResized(_:)), name: NSTableView.columnDidResizeNotification,
      object: table)
    reload()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func windowDidLoad() {
    super.windowDidLoad()
    window?.makeFirstResponder(table)
  }
  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    window?.makeFirstResponder(table)
  }
  func reload() {
    retainUnusedGrowth()
    resizing = true
    rowHeights.removeAll()
    table.delegate = nil
    table.dataSource = nil
    for column in table.tableColumns { table.removeTableColumn(column) }
    if columnOffset == 1 {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("numbers"))
      column.width = 42
      column.minWidth = 42
      column.maxWidth = 42
      table.addTableColumn(column)
    }
    for value in doc.model.columns {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(value.id.uuidString))
      column.width = value.width
      column.minWidth = 60
      column.maxWidth = 2000
      table.addTableColumn(column)
    }
    selectedRow = min(selectedRow, doc.model.rows.count - 1)
    selectedColumn = min(selectedColumn, doc.model.columns.count - 1)
    anchorRow = selectedRow
    anchorColumn = selectedColumn
    table.dataSource = self
    table.delegate = self
    table.reloadData()
    resizing = false
    updateStatus()
  }
  func numberOfRows(in tableView: NSTableView) -> Int { doc.model.rows.count }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    GridRowView()
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard doc.model.rows.indices.contains(row), let tableColumn,
      let index = table.tableColumns.firstIndex(of: tableColumn),
      index - columnOffset < doc.model.columns.count
    else { return nil }
    let identifier = NSUserInterfaceItemIdentifier("cell")
    let cell =
      (table.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
      ?? NSTableCellView()
    if cell.textField == nil {
      cell.identifier = identifier
      let field = NSTextField(labelWithString: "")
      field.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(field)
      cell.textField = field
      NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
        field.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
        field.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -3),
      ])
    }
    let c = index - columnOffset
    let field = cell.textField!
    field.stringValue = c < 0 ? (row == 0 ? "" : String(row)) : doc.model.rows[row].cells[c]
    field.font =
      row == 0
      ? .boldSystemFont(ofSize: doc.model.fontSize) : .systemFont(ofSize: doc.model.fontSize)
    field.textColor = c < 0 ? .secondaryLabelColor : .labelColor
    field.maximumNumberOfLines = 0
    field.lineBreakMode = doc.model.wraps ? .byWordWrapping : .byClipping
    field.cell?.wraps = doc.model.wraps
    field.cell?.isScrollable = false
    field.alignment = c < 0 ? .right : alignment(c)
    field.setAccessibilityLabel(
      c < 0 ? "Row \(row)" : "\(columnName(c))\(row): \(field.stringValue)")
    cell.wantsLayer = true
    cell.layer?.backgroundColor =
      (row == 0 ? NSColor.controlBackgroundColor : NSColor.textBackgroundColor).cgColor
    return cell
  }
  private func alignment(_ column: Int) -> NSTextAlignment {
    switch doc.model.columns[column].alignment {
    case 1: return .center
    case 2: return .right
    default: return .left
    }
  }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard doc.model.rows.indices.contains(row) else { return 26 }
    if let height = rowHeights[row] { return height }
    let font =
      row == 0
      ? NSFont.boldSystemFont(ofSize: doc.model.fontSize)
      : NSFont.systemFont(ofSize: doc.model.fontSize)
    var height: CGFloat = ceil(font.ascender - font.descender + font.leading) + 8
    for c in doc.model.columns.indices {
      let text = doc.model.rows[row].cells[c]
      let width = doc.model.wraps ? max(40, doc.model.columns[c].width - 12) : 1_000_000
      let rect = (text as NSString).boundingRect(
        with: NSSize(width: width, height: 100000),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
      height = max(height, ceil(rect.height) + 9)
    }
    // Very long cells remain editable in the cell's scrollable text editor.
    height = min(600, height)
    rowHeights[row] = height
    return height
  }
  @objc func columnResized(_ notification: Notification) {
    guard !resizing else { return }
    finishEditing()
    let widths = table.tableColumns.dropFirst(columnOffset).map(\.width)
    guard widths.count == doc.model.columns.count else { return }
    doc.change("Resize Column") { model in
      for c in model.columns.indices { model.columns[c].width = widths[c] }
    }
    rowHeights.removeAll()
    table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<doc.model.rows.count))
  }
  func select(row: Int, column: Int, extend: Bool = false) {
    finishEditing()
    selectedRow = max(0, min(row, doc.model.rows.count - 1))
    selectedColumn = max(0, min(column, doc.model.columns.count - 1))
    if !extend {
      anchorRow = selectedRow
      anchorColumn = selectedColumn
    }
    removeUnusedGrowth()
    table.scrollRowToVisible(selectedRow)
    table.scrollColumnToVisible(selectedColumn + columnOffset)
    table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    table.needsDisplay = true
    updateStatus()
  }
  func move(dx: Int, dy: Int, extend: Bool = false, edge: Bool = false) {
    finishEditing()
    var row = selectedRow + dy
    var column = selectedColumn + dx
    if edge {
      if dx != 0 { column = dx < 0 ? 0 : doc.model.columns.count - 1 }
      if dy != 0 { row = dy < 0 ? 0 : doc.model.rows.count - 1 }
    }
    // One-cell growth keeps keyboard entry continuous, without pre-sizing a sheet.
    if row >= doc.model.rows.count || column >= doc.model.columns.count {
      doc.change("Grow Table") { model in
        if row >= model.rows.count {
          model.insertRow(at: model.rows.count)
          automaticRows.insert(model.rows.last!.id)
        }
        if column >= model.columns.count {
          model.insertColumn(at: model.columns.count)
          automaticColumns.insert(model.columns.last!.id)
        }
      }
      reload()
    }
    select(row: row, column: column, extend: extend)
    window?.makeFirstResponder(table)
  }
  // Once content is committed, an automatically added edge becomes an ordinary edge.
  func retainUnusedGrowth() {
    automaticRows.formIntersection(
      doc.model.rows.filter { $0.cells.allSatisfy(\.isEmpty) }.map(\.id))
    automaticColumns.formIntersection(
      doc.model.columns.indices.filter { c in
        doc.model.rows.allSatisfy { $0.cells[c].isEmpty }
      }.map { doc.model.columns[$0].id })
  }
  private func removeUnusedGrowth() {
    retainUnusedGrowth()
    let range = selection
    let oldRowCount = doc.model.rows.count
    let oldColumnCount = doc.model.columns.count
    doc.change("Remove Unused Growth") { model in
      while model.rows.count - 1 > range.rows.upperBound,
        automaticRows.contains(model.rows.last!.id)
      {
        model.removeRow(at: model.rows.count - 1)
      }
      while model.columns.count - 1 > range.columns.upperBound,
        automaticColumns.contains(model.columns.last!.id)
      {
        model.removeColumn(at: model.columns.count - 1)
      }
    }
    if oldRowCount != doc.model.rows.count || oldColumnCount != doc.model.columns.count {
      let anchor = (anchorRow, anchorColumn)
      reload()
      anchorRow = anchor.0
      anchorColumn = anchor.1
    }
  }
  func beginEditing(replace: Bool = false) {
    finishEditing()
    anchorRow = selectedRow
    anchorColumn = selectedColumn
    editRow = selectedRow
    editColumn = selectedColumn
    let frame = table.frameOfCell(atColumn: editColumn + columnOffset, row: editRow)
    let container = NSScrollView(frame: frame.insetBy(dx: 1, dy: 1))
    container.borderType = .noBorder
    // Scroller chrome can consume almost all of a single-line cell. Keep the
    // clip view scrollable (including caret tracking) without drawing scrollers.
    container.hasVerticalScroller = false
    container.hasHorizontalScroller = false
    let text = CellTextView(frame: NSRect(origin: .zero, size: container.contentSize))
    text.owner = self
    text.delegate = self
    text.isRichText = false
    text.importsGraphics = false
    text.font = .systemFont(ofSize: doc.model.fontSize)
    text.textColor = .labelColor
    text.backgroundColor = .textBackgroundColor
    text.insertionPointColor = .controlAccentColor
    text.textContainerInset = NSSize(width: 3, height: 3)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = !doc.model.wraps
    text.minSize = NSSize(width: 0, height: container.contentSize.height)
    text.maxSize = NSSize(width: 1_000_000, height: 1_000_000)
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = doc.model.wraps
    text.textContainer?.containerSize = NSSize(
      width: doc.model.wraps ? container.contentSize.width : 1_000_000, height: 1_000_000)
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.allowsUndo = true
    text.string = replace ? "" : doc.model.rows[editRow].cells[editColumn]
    text.setAccessibilityLabel("Edit \(columnName(editColumn))\(editRow)")
    container.documentView = text
    table.addSubview(container)
    editorScroll = container
    editor = text
    window?.makeFirstResponder(text)
    text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
    updateStatus()
  }
  func modelForSaving() -> TableModel {
    var snapshot = doc.model
    if let editor { snapshot.rows[editRow].cells[editColumn] = editor.string }
    return snapshot
  }
  func finishEditing() {
    guard let editor else { return }
    // Commit marked text before ending an edit explicitly through mouse/menu actions.
    editor.unmarkText()
    let value = editor.string
    self.editor = nil
    doc.change("Edit Cell") { $0.rows[editRow].cells[editColumn] = value }
    editorScroll?.removeFromSuperview()
    editorScroll = nil
    rowHeights.removeValue(forKey: editRow)
    table.reloadData(
      forRowIndexes: IndexSet(integer: editRow),
      columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
    table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: editRow))
    window?.makeFirstResponder(table)
    updateStatus()
  }
  func cancelEditing() {
    if let editor, editor.string != doc.model.rows[editRow].cells[editColumn] {
      // An autosave may already contain the draft; cancellation must save the original again.
      doc.updateChangeCount(.changeDone)
    }
    editor = nil
    editorScroll?.removeFromSuperview()
    editorScroll = nil
    window?.makeFirstResponder(table)
    updateStatus()
  }
  func textDidChange(_ notification: Notification) {
    doc.updateChangeCount(.changeDone)
  }
  func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    guard !textView.hasMarkedText() else { return false }
    switch NSStringFromSelector(commandSelector) {
    case "insertTab:": move(dx: 1, dy: 0)
    case "insertBacktab:": move(dx: -1, dy: 0)
    case "insertNewline:": move(dx: 0, dy: 1)
    case "cancelOperation:": cancelEditing()
    case "moveLeft:":
      guard textView.selectedRange().length == 0, textView.selectedRange().location == 0 else {
        return false
      }
      move(dx: -1, dy: 0)
    case "moveRight:":
      guard textView.selectedRange().length == 0,
        textView.selectedRange().location == (textView.string as NSString).length
      else { return false }
      move(dx: 1, dy: 0)
    case "moveUp:":
      guard textView.selectedRange().location == 0 else { return false }
      move(dx: 0, dy: -1)
    case "moveDown:":
      guard textView.selectedRange().location == (textView.string as NSString).length else {
        return false
      }
      move(dx: 0, dy: 1)
    default: return false
    }
    return true
  }
  private func columnName(_ value: Int) -> String {
    var n = value + 1
    var result = ""
    while n > 0 {
      n -= 1
      result = String(UnicodeScalar(65 + n % 26)!) + result
      n /= 26
    }
    return result
  }
  func updateStatus(_ message: String? = nil) {
    status.stringValue =
      message
      ?? "\(columnName(selectedColumn))\(selectedRow)  ·  \(doc.model.rows.count - 1) rows × \(doc.model.columns.count) columns   ·   "
      + (editor == nil
        ? "⌃A Edit at start    ⌃E Edit at end    ⇥ Next cell    ⌘⌥C Copy cell link"
        : "⌥↩ Line break    ⇥ Next cell    Esc Cancel")
  }
  private func mutate(_ name: String, _ body: (inout TableModel) -> Void) {
    finishEditing()
    doc.change(name, body)
    reload()
    window?.makeFirstResponder(table)
  }
  func insertRow(above: Bool) {
    let index = max(1, selectedRow + (above ? 0 : 1))
    mutate("Insert Row") { $0.insertRow(at: index) }
    select(row: index, column: selectedColumn)
  }
  func insertColumn(before: Bool) {
    let index = selectedColumn + (before ? 0 : 1)
    mutate("Insert Column") { $0.insertColumn(at: index) }
    select(row: selectedRow, column: index)
  }
  @objc func rowAbove(_ sender: Any?) { insertRow(above: true) }
  @objc func rowBelow(_ sender: Any?) { insertRow(above: false) }
  @objc func rowEnd(_ sender: Any?) {
    mutate("Append Row") { $0.insertRow(at: $0.rows.count) }
    select(row: doc.model.rows.count - 1, column: selectedColumn)
  }
  @objc func columnBefore(_ sender: Any?) { insertColumn(before: true) }
  @objc func columnAfter(_ sender: Any?) { insertColumn(before: false) }
  @objc func columnEnd(_ sender: Any?) {
    mutate("Append Column") { $0.insertColumn(at: $0.columns.count) }
    select(row: selectedRow, column: doc.model.columns.count - 1)
  }
  @objc func removeRow(_ sender: Any?) { mutate("Remove Row") { $0.removeRow(at: selectedRow) } }
  @objc func removeColumn(_ sender: Any?) {
    mutate("Remove Column") { $0.removeColumn(at: selectedColumn) }
  }
  @objc func toggleWrap(_ sender: Any?) { mutate("Wrap Cells") { $0.wraps.toggle() } }
  @objc func toggleRowNumbers(_ sender: Any?) {
    mutate("Row Numbers") { $0.showsRowNumbers.toggle() }
  }
  @objc func editCell(_ sender: Any?) { beginEditing() }
  @objc func alignLeft(_ sender: Any?) { setAlignment(0) }
  @objc func alignCenter(_ sender: Any?) { setAlignment(1) }
  @objc func alignRight(_ sender: Any?) { setAlignment(2) }
  private func setAlignment(_ value: Int) {
    let columns = selection.columns
    mutate("Align Columns") { model in for c in columns { model.columns[c].alignment = value } }
  }
  @objc func zoomIn(_ sender: Any?) {
    scroll.magnification = min(scroll.maxMagnification, scroll.magnification + 0.1)
  }
  @objc func zoomOut(_ sender: Any?) {
    scroll.magnification = max(scroll.minMagnification, scroll.magnification - 0.1)
  }
  @objc func prune(_ sender: Any?) {
    mutate("Prune Empty Edges") { model in
      while model.rows.count > 2, model.rows.last!.cells.allSatisfy(\.isEmpty) {
        model.rows.removeLast()
      }
      while model.columns.count > 1, model.rows.allSatisfy({ $0.cells.last!.isEmpty }) {
        model.removeColumn(at: model.columns.count - 1)
      }
    }
  }
  @objc func clearCells(_ sender: Any?) {
    let range = selection
    mutate("Clear Cells") { model in
      for r in range.rows { for c in range.columns { model.rows[r].cells[c] = "" } }
    }
  }
  @objc override func selectAll(_ sender: Any?) {
    finishEditing()
    anchorRow = 0
    anchorColumn = 0
    select(row: doc.model.rows.count - 1, column: doc.model.columns.count - 1, extend: true)
  }
  @objc func copy(_ sender: Any?) {
    finishEditing()
    let range = selection
    let matrix = range.rows.map { r in range.columns.map { doc.model.rows[r].cells[$0] } }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(TableText.delimited(matrix, separator: "\t"), forType: .string)
    if let data = try? JSONEncoder().encode(matrix) {
      NSPasteboard.general.setData(data, forType: .init("com.kazuhideoki.tablin.cells"))
    }
  }
  @objc func cut(_ sender: Any?) {
    copy(sender)
    clearCells(sender)
  }
  @objc func paste(_ sender: Any?) {
    finishEditing()
    do {
      let matrix: [[String]]
      if let data = NSPasteboard.general.data(forType: .init("com.kazuhideoki.tablin.cells")) {
        matrix = try JSONDecoder().decode([[String]].self, from: data)
      } else if let text = NSPasteboard.general.string(forType: .string) {
        matrix = try TableText.parseDelimited(text, separator: "\t")
      } else {
        return
      }
      mutate("Paste Cells") { $0.paste(matrix, row: selectedRow, column: selectedColumn) }
    } catch { presentError(error) }
  }
  @objc func copyMarkdown(_ sender: Any?) {
    finishEditing()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      TableText.markdown(doc.model.rows.map(\.cells)), forType: .string)
  }
  @objc func copyCellLink(_ sender: Any?) {
    finishEditing()
    let rowID = doc.model.rows[selectedRow].id
    let columnID = doc.model.columns[selectedColumn].id
    if doc.fileURL == nil {
      pendingLinkCell = (rowID, columnID)
      doc.save(
        withDelegate: self, didSave: #selector(savedForLink(_:didSave:contextInfo:)),
        contextInfo: nil)
    } else if let url = doc.fileURL {
      // Persist structural IDs before handing a link to another application.
      doc.save(to: url, ofType: tablinType, for: .saveOperation) { [weak self] error in
        if let error {
          self?.presentError(error)
        } else {
          self?.putCellLink(rowID: rowID, columnID: columnID)
        }
      }
    }
  }
  @objc private func savedForLink(
    _ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?
  ) {
    defer { pendingLinkCell = nil }
    if didSave, let cell = pendingLinkCell { putCellLink(rowID: cell.row, columnID: cell.column) }
  }
  private func putCellLink(rowID: UUID, columnID: UUID) {
    guard let url = doc.fileURL else { return }
    guard let row = doc.model.rows.firstIndex(where: { $0.id == rowID }),
      let column = doc.model.columns.firstIndex(where: { $0.id == columnID })
    else {
      presentError(TableError.missingCell)
      return
    }
    DocumentLocations.remember(doc.model.id, url: url)
    let link = doc.model.link(file: url, row: row, column: column)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(link.absoluteString, forType: .string)
    NSPasteboard.general.setString(link.absoluteString, forType: .URL)
    updateStatus("Copied link to \(columnName(column))\(row)")
  }
  @objc func exportCSV(_ sender: Any?) { export(ext: "csv") }
  @objc func exportMarkdown(_ sender: Any?) { export(ext: "md") }
  private func export(ext: String) {
    finishEditing()
    guard let window else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "\(((doc.displayName ?? "Untitled") as NSString).deletingPathExtension).\(ext)"
    panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      do {
        let matrix = self.doc.model.rows.map(\.cells)
        let text = ext == "csv" ? TableText.delimited(matrix) : TableText.markdown(matrix)
        try text.write(to: url, atomically: true, encoding: .utf8)
      } catch { self.presentError(error) }
    }
  }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleWrap(_:)) {
      menuItem.state = doc.model.wraps ? .on : .off
    }
    if menuItem.action == #selector(toggleRowNumbers(_:)) {
      menuItem.state = doc.model.showsRowNumbers ? .on : .off
    }
    if menuItem.action == #selector(removeRow(_:)) {
      return selectedRow > 0 && doc.model.rows.count > 1
    }
    if menuItem.action == #selector(removeColumn(_:)) { return doc.model.columns.count > 1 }
    return true
  }
  private let toolbarIDs = [
    "numbers", "columns", "removeColumn", "rows", "removeRow", "alignment", "prune",
    "NSToolbarFlexibleSpaceItem", "wrap", "link",
  ]
  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarIDs.map { NSToolbarItem.Identifier($0) }
  }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }
  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    if id == .flexibleSpace { return NSToolbarItem(itemIdentifier: id) }
    func button(_ title: String, symbol: String, action: Selector) -> NSToolbarItem {
      let item = NSToolbarItem(itemIdentifier: id)
      item.label = title
      item.toolTip = title
      item.isBordered = false
      item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
      item.target = self
      item.action = action
      return item
    }
    func group(_ title: String, symbols: [String], labels: [String], actions: [Selector])
      -> NSToolbarItem
    {
      let group = NSToolbarItemGroup(itemIdentifier: id)
      group.label = title
      group.subitems = zip(zip(symbols, labels), actions).enumerated().map { i, pair in
        let ((symbol, label), action) = pair
        let item = NSToolbarItem(itemIdentifier: .init(id.rawValue + String(i)))
        item.isBordered = false
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
      }
      return group
    }
    switch id.rawValue {
    case "numbers":
      return button("Row Numbers", symbol: "list.number", action: #selector(toggleRowNumbers(_:)))
    case "columns":
      return group(
        "Columns",
        symbols: [
          "rectangle.lefthalf.inset.filled.arrow.left",
          "rectangle.righthalf.inset.filled.arrow.right", "rectangle.split.3x1",
        ], labels: ["Before", "After", "End"],
        actions: [
          #selector(columnBefore(_:)), #selector(columnAfter(_:)), #selector(columnEnd(_:)),
        ])
    case "removeColumn":
      return button(
        "Remove Col", symbol: "rectangle.split.3x1", action: #selector(removeColumn(_:)))
    case "rows":
      return group(
        "Rows", symbols: ["arrow.up.to.line", "arrow.down.to.line", "arrow.down.to.line"],
        labels: ["Above", "Below", "Bottom"],
        actions: [#selector(rowAbove(_:)), #selector(rowBelow(_:)), #selector(rowEnd(_:))])
    case "removeRow":
      return button("Remove Row", symbol: "minus.rectangle", action: #selector(removeRow(_:)))
    case "alignment":
      return group(
        "Alignment", symbols: ["text.alignleft", "text.aligncenter", "text.alignright"],
        labels: ["Left", "Center", "Right"],
        actions: [#selector(alignLeft(_:)), #selector(alignCenter(_:)), #selector(alignRight(_:))])
    case "prune": return button("Prune", symbol: "scissors", action: #selector(prune(_:)))
    case "wrap":
      return button("Wrap", symbol: "text.word.spacing", action: #selector(toggleWrap(_:)))
    case "link": return button("Copy Link", symbol: "link", action: #selector(copyCellLink(_:)))
    default: return nil
    }
  }
}
