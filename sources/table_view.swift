import AppKit

final class GridRowView: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {}
  override var isEmphasized: Bool {
    get { false }
    set {}
  }
}
final class GridTableView: NSTableView {
  weak var owner: TableWindowController?
  private var resizingColumn: Int?
  private var resizeStartX: CGFloat = 0
  private var resizeStartWidth: CGFloat = 0
  override func accessibilityChildren() -> [Any]? {
    var children = super.accessibilityChildren() ?? []
    if let editor = owner?.editor { children.append(editor) }
    return children
  }
  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if row(at: point) == 0 {
      for c in tableColumns.indices where c >= (owner?.columnOffset ?? 0) {
        if abs(point.x - rect(ofColumn: c).maxX) <= 5 {
          owner?.finishEditing()
          resizingColumn = c
          resizeStartX = point.x
          resizeStartWidth = tableColumns[c].width
          return
        }
      }
    }
    let r = row(at: point)
    let c = column(at: point) - (owner?.columnOffset ?? 0)
    guard r >= 0, c >= 0 else {
      owner?.finishEditing()
      return
    }
    owner?.select(row: r, column: c, extend: event.modifierFlags.contains(.shift))
    window?.makeFirstResponder(self)
    if event.clickCount == 2 { owner?.beginEditing() }
  }
  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let column = resizingColumn {
      tableColumns[column].width = max(60, min(2000, resizeStartWidth + point.x - resizeStartX))
      return
    }
    let r = row(at: point)
    let c = column(at: point) - (owner?.columnOffset ?? 0)
    if r >= 0 && c >= 0 { owner?.select(row: r, column: c, extend: true) }
    autoscroll(with: event)
  }
  override func mouseUp(with event: NSEvent) { resizingColumn = nil }
  override func resetCursorRects() {
    super.resetCursorRects()
    guard numberOfRows > 0 else { return }
    for c in tableColumns.indices where c >= (owner?.columnOffset ?? 0) {
      let rect = frameOfCell(atColumn: c, row: 0)
      addCursorRect(
        NSRect(x: rect.maxX - 4, y: rect.minY, width: 8, height: rect.height),
        cursor: .resizeLeftRight)
    }
  }
  override func keyDown(with event: NSEvent) {
    guard let owner else { return }
    let option = event.modifierFlags.contains(.option)
    let shift = event.modifierFlags.contains(.shift)
    let command = event.modifierFlags.contains(.command)
    switch event.keyCode {
    case 123, 124, 125, 126:
      if option {
        switch event.keyCode {
        case 123: owner.insertColumn(before: true)
        case 124: owner.insertColumn(before: false)
        case 126: owner.insertRow(above: true)
        default: owner.insertRow(above: false)
        }
      } else {
        let dx = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : 0
        let dy = event.keyCode == 126 ? -1 : event.keyCode == 125 ? 1 : 0
        owner.move(dx: dx, dy: dy, extend: shift, edge: command)
      }
    case 48: owner.move(dx: shift ? -1 : 1, dy: 0)
    case 36, 76:
      if option { owner.beginEditing() } else { owner.move(dx: 0, dy: shift ? -1 : 1) }
    case 51, 117: owner.clearCells(nil)
    case 53: owner.select(row: owner.selectedRow, column: owner.selectedColumn)
    default:
      guard !command, !event.modifierFlags.contains(.control), let string = event.characters,
        !string.isEmpty
      else {
        super.keyDown(with: event)
        return
      }
      owner.beginEditing(replace: true)
      owner.editor?.keyDown(with: event)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let owner, numberOfRows > 0, numberOfColumns > 0 else { return }
    let dataWidth = tableColumns.reduce(0) { $0 + $1.width + intercellSpacing.width }
    let dataHeight = rect(ofRow: numberOfRows - 1).maxY
    gridColor.setStroke()
    let grid = NSBezierPath()
    grid.lineWidth = 0.5
    let visibleRows = rows(in: dirtyRect)
    if visibleRows.location != NSNotFound {
      for r in visibleRows.location..<min(numberOfRows, NSMaxRange(visibleRows)) {
        let y = rect(ofRow: r).maxY
        grid.move(to: NSPoint(x: 0, y: y))
        grid.line(to: NSPoint(x: dataWidth, y: y))
      }
    }
    for c in tableColumns.indices {
      let x = rect(ofColumn: c).maxX
      grid.move(to: NSPoint(x: x, y: 0))
      grid.line(to: NSPoint(x: x, y: dataHeight))
    }
    grid.stroke()
    let range = owner.selection
    let first = frameOfCell(
      atColumn: range.columns.lowerBound + owner.columnOffset, row: range.rows.lowerBound)
    let last = frameOfCell(
      atColumn: range.columns.upperBound + owner.columnOffset, row: range.rows.upperBound)
    let rect = first.union(last).insetBy(dx: 0.5, dy: 0.5)
    NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
    rect.fill()
    NSColor.controlAccentColor.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = 1.5
    path.stroke()
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    let point = convert(event.locationInWindow, from: nil)
    let r = row(at: point)
    let c = column(at: point) - (owner?.columnOffset ?? 0)
    if r >= 0 && c >= 0, let owner,
      !(owner.selection.rows.contains(r) && owner.selection.columns.contains(c))
    {
      owner.select(row: r, column: c)
    }
    let menu = NSMenu()
    for (title, action) in [
      ("Copy", #selector(TableWindowController.copy(_:))),
      ("Paste", #selector(TableWindowController.paste(_:))),
      ("Copy Link to Cell", #selector(TableWindowController.copyCellLink(_:))),
      ("Edit Cell", #selector(TableWindowController.editCell(_:))),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = owner
    }
    return menu
  }
  @objc func copy(_ sender: Any?) { owner?.copy(sender) }
  @objc func cut(_ sender: Any?) { owner?.cut(sender) }
  @objc func paste(_ sender: Any?) { owner?.paste(sender) }
  @objc override func selectAll(_ sender: Any?) { owner?.selectAll(sender) }
}

final class CellTextView: NSTextView {
  private let editingUndoManager = UndoManager()
  override var undoManager: UndoManager? { editingUndoManager }
  weak var owner: TableWindowController?
  override func keyDown(with event: NSEvent) {
    if !hasMarkedText(), event.modifierFlags.contains(.option), [36, 76].contains(event.keyCode) {
      insertText("\n", replacementRange: selectedRange())
      return
    }
    if !hasMarkedText(), event.modifierFlags.contains(.shift), [36, 76].contains(event.keyCode) {
      owner?.move(dx: 0, dy: -1)
      return
    }
    super.keyDown(with: event)
  }
}
