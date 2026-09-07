import AppKit
import UniformTypeIdentifiers

let tablinType = "com.kazuhideoki.tablin.table"

@objc(TablinDocument)
final class TablinDocument: NSDocument {
  var model = TableModel()
  var tableController: TableWindowController? { windowControllers.first as? TableWindowController }
  override class var autosavesInPlace: Bool { true }
  override init() {
    super.init()
    hasUndoManager = true
  }
  override func makeWindowControllers() {
    addWindowController(TableWindowController(document: self))
  }
  override func data(ofType typeName: String) throws -> Data {
    let snapshot = tableController?.modelForSaving() ?? model
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(snapshot.validated())
  }
  override func read(from data: Data, ofType typeName: String) throws {
    model = try JSONDecoder().decode(TableModel.self, from: data).validated()
    tableController?.reload()
  }
  override func write(to url: URL, ofType typeName: String) throws {
    try super.write(to: url, ofType: typeName)
    DocumentLocations.remember(model.id, url: url)
  }
  override func read(from url: URL, ofType typeName: String) throws {
    try super.read(from: url, ofType: typeName)
    DocumentLocations.remember(model.id, url: url)
  }
  func change(_ name: String, _ body: (inout TableModel) -> Void) {
    let old = model
    var next = old
    body(&next)
    guard next != old else { return }
    model = next
    undoManager?.registerUndo(withTarget: self) { target in target.restore(old, name: name) }
    undoManager?.setActionName(name)
    updateChangeCount(.changeDone)
  }
  private func restore(_ value: TableModel, name: String) {
    tableController?.cancelEditing()
    let old = model
    undoManager?.registerUndo(withTarget: self) { target in target.restore(old, name: name) }
    undoManager?.setActionName(name)
    model = value
    updateChangeCount(.changeDone)
    tableController?.reload()
  }
}

enum DocumentLocations {
  static func remember(_ id: UUID, url: URL) {
    guard
      let bookmark = try? url.bookmarkData(
        options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return }
    UserDefaults.standard.set(bookmark, forKey: "document." + id.uuidString)
  }
  static func locate(_ link: CellLink) -> URL {
    if let data = UserDefaults.standard.data(forKey: "document." + link.document.uuidString) {
      var stale = false
      if let url = try? URL(
        resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
        bookmarkDataIsStale: &stale),
        FileManager.default.fileExists(atPath: url.path)
      {
        return url
      }
    }
    return URL(fileURLWithPath: link.path)
  }
}

final class TablinDocumentController: NSDocumentController {
  override var defaultType: String? { tablinType }
  override func documentClass(forType typeName: String) -> AnyClass? { TablinDocument.self }
  override func typeForContents(of url: URL) throws -> String {
    guard url.pathExtension.lowercased() == "tablin" else { throw TableError.invalidDocument }
    return tablinType
  }
}
