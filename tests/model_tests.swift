import Foundation

@main struct Tests {
  static func main() throws {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      precondition(condition(), message)
      checks += 1
      print("PASS \(message)")
    }
    func rejects(_ message: String, _ body: () throws -> Void) {
      do {
        try body()
        preconditionFailure(message)
      } catch {
        checks += 1
        print("PASS \(message)")
      }
    }
    let matrix = [["項目", "説明", "結果"], ["日本語 🐳", "第一行\n第二行", "a,\"b\""], ["空欄", "", "x\ty"]]
    var model = TableModel(matrix: matrix)
    model.wraps = true
    model.showsRowNumbers = true
    model.columns[1].width = 245
    model.columns[1].alignment = 2
    let data = try JSONEncoder().encode(model)
    let restored = try JSONDecoder().decode(TableModel.self, from: data).validated()
    check(
      restored == model, "native round trip preserves IDs, multiline, Unicode and view settings")
    let file = URL(fileURLWithPath: "/private/tmp/日本語 & # テーブル.tablin")
    let url = model.link(file: file, row: 1, column: 1)
    let expectedScheme = ProcessInfo.processInfo.environment["TABLIN_EXPECTED_SCHEME"] ?? "tablin"
    check(url.scheme == expectedScheme, "cell link uses this app's registered scheme")
    var foreignURL = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    foreignURL.scheme = "tablin-dev-another-worktree"
    rejects("another worktree's cell link is rejected") { _ = try CellLink(foreignURL.url!) }
    let link = try CellLink(url)
    check(link.path == file.path, "URL escaping of Japanese, space, ampersand and hash")
    model.insertRow(at: 1)
    model.insertColumn(at: 0)
    let position = try model.position(for: link)
    check(
      position.row == 2 && position.column == 2,
      "deep link remains on original cell after row and column insertion")
    check(
      model.rows[position.row].cells[position.column] == "第一行\n第二行",
      "deep link selects original multiline content")
    model.rows.swapAt(1, 2)
    let reordered = try model.position(for: link)
    check(reordered.row == 1, "deep link survives row reorder")
    model.removeRow(at: reordered.row)
    rejects("deleted cell is reported, never redirected") { _ = try model.position(for: link) }
    rejects("wrong document identity is rejected") { _ = try TableModel().position(for: link) }
    rejects("invalid URL is rejected") { _ = try CellLink(URL(string: "tablin://open?row=1")!) }
    rejects("duplicate URL parameters are rejected") {
      _ = try CellLink(URL(string: url.absoluteString + "&row=" + link.row.uuidString)!)
    }
    let csv = TableText.delimited(matrix)
    check(
      tryValue { try TableText.parseDelimited(csv) } == matrix,
      "CSV round trip preserves multiline, quotes and commas")
    check(
      tryValue { try TableText.parseDelimited("A,B\r\n\"one\r\ntwo\",\"x\"\"y\"\r\n") } == [
        ["A", "B"], ["one\ntwo", "x\"y"],
      ], "RFC-style CRLF and escaped quotes")
    check(
      tryValue { try TableText.parseDelimited("\u{FEFF}A,B\n1,2") } == [["A", "B"], ["1", "2"]],
      "UTF-8 BOM is not cell content")
    let tsv = TableText.delimited(matrix, separator: "\t")
    check(
      tryValue { try TableText.parseDelimited(tsv, separator: "\t") } == matrix,
      "clipboard TSV round trip preserves embedded tabs and newlines")
    rejects("unterminated CSV quote rejected") { _ = try TableText.parseDelimited("\"broken") }
    rejects("characters after closing CSV quote rejected") {
      _ = try TableText.parseDelimited("\"ok\"bad")
    }
    let markdownMatrix = [["項目", "説明"], ["a|b", "one\ntwo"], ["<br>", "\\ & < >"]]
    let markdown = TableText.markdown(markdownMatrix)
    check(
      tryValue { try TableText.parseMarkdown(markdown) } == markdownMatrix,
      "Markdown round trip preserves pipes, HTML literals, backslashes and newlines")
    check(
      tryValue {
        try TableText.parseMarkdown("# title\n\n| a | b |\n| :--- | ---: |\n| x\\|y | z |\n\nend")
      } == [["a", "b"], ["x|y", "z"]],
      "Markdown import locates first table and handles escaped pipe")
    var pasted = TableModel(matrix: [["header"]])
    pasted.paste([["a", "b"], ["c", "d"]], row: 1, column: 1)
    check(
      pasted.rows.count == 3 && pasted.columns.count == 3 && pasted.rows[2].cells[2] == "d",
      "rectangular paste grows rows and columns")
    _ = try pasted.validated()
    var broken = pasted
    broken.columns[0].width = -1
    rejects("invalid document dimensions rejected") { _ = try broken.validated() }
    broken = pasted
    broken.rows[0].cells.removeLast()
    rejects("ragged document rejected") { _ = try broken.validated() }
    broken = pasted
    broken.rows[1].id = broken.rows[0].id
    rejects("duplicate row identity rejected") { _ = try broken.validated() }
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
      "tablin_tests_" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let saved = root.appendingPathComponent("比較.tablin")
    try data.write(to: saved, options: .atomic)
    check(
      tryValue { try JSONDecoder().decode(TableModel.self, from: Data(contentsOf: saved)) }
        == restored, "atomic disk save and reload")
    let start = Date()
    let large = TableModel(matrix: (0..<10001).map { r in (0..<12).map { "\(r):\($0) 日本語" } })
    let largeData = try JSONEncoder().encode(large)
    let decoded = try JSONDecoder().decode(TableModel.self, from: largeData).validated()
    check(
      decoded.rows.count == 10001 && decoded.columns.count == 12,
      "10,000 data rows × 12 columns encode/decode")
    print(String(format: "Large document round trip: %.3f s", Date().timeIntervalSince(start)))
    print("\(checks) checks passed")
  }
  static func tryValue<T>(_ body: () throws -> T) -> T? { try? body() }
}
