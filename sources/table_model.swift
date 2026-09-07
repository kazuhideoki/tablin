import Foundation

// Command-line tests have no app bundle; production and dev apps use their registered scheme.
let tablinURLScheme: String = {
  guard let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
    let schemes = types.first?["CFBundleURLSchemes"] as? [String], let scheme = schemes.first
  else { return "tablin" }
  return scheme
}()

struct TableColumn: Codable, Equatable {
  var id = UUID()
  var width: Double = 180
  var alignment: Int = 0
}
struct TableRow: Codable, Equatable {
  var id = UUID()
  var cells: [String]
}
struct TableModel: Codable, Equatable {
  var version = 1
  var id = UUID()
  var columns: [TableColumn]
  var rows: [TableRow]
  var wraps = false
  var showsRowNumbers = false
  var fontSize: Double = 13

  init(matrix: [[String]] = [["", "", ""], ["", "", ""], ["", "", ""]]) {
    let count = max(1, matrix.map(\.count).max() ?? 1)
    columns = (0..<count).map { _ in TableColumn() }
    rows = (matrix.isEmpty ? [[""]] : matrix).map {
      TableRow(cells: $0 + Array(repeating: "", count: count - $0.count))
    }
  }
  func validated() throws -> Self {
    guard version == 1, !columns.isEmpty, !rows.isEmpty,
      Set(columns.map(\.id)).count == columns.count,
      Set(rows.map(\.id)).count == rows.count,
      rows.allSatisfy({ $0.cells.count == columns.count }),
      columns.allSatisfy({
        $0.width.isFinite && (60...2000).contains($0.width) && (0...2).contains($0.alignment)
      }),
      fontSize.isFinite, (9...32).contains(fontSize)
    else {
      throw TableError.invalidDocument
    }
    return self
  }
  mutating func insertRow(at index: Int) {
    rows.insert(TableRow(cells: Array(repeating: "", count: columns.count)), at: index)
  }
  mutating func insertColumn(at index: Int) {
    columns.insert(TableColumn(), at: index)
    for i in rows.indices { rows[i].cells.insert("", at: index) }
  }
  mutating func removeRow(at index: Int) {
    guard rows.count > 1, index > 0 else { return }
    rows.remove(at: index)
  }
  mutating func removeColumn(at index: Int) {
    guard columns.count > 1 else { return }
    columns.remove(at: index)
    for i in rows.indices { rows[i].cells.remove(at: index) }
  }
  mutating func paste(_ matrix: [[String]], row: Int, column: Int) {
    let width = matrix.map(\.count).max() ?? 0
    while rows.count < row + matrix.count { insertRow(at: rows.count) }
    while columns.count < column + width { insertColumn(at: columns.count) }
    for (r, values) in matrix.enumerated() {
      for (c, value) in values.enumerated() { rows[row + r].cells[column + c] = value }
    }
  }
  func link(file: URL, row: Int, column: Int) -> URL {
    var parts = URLComponents()
    parts.scheme = tablinURLScheme
    parts.host = "open"
    parts.queryItems = [
      URLQueryItem(name: "document", value: id.uuidString),
      URLQueryItem(name: "row", value: rows[row].id.uuidString),
      URLQueryItem(name: "column", value: columns[column].id.uuidString),
      URLQueryItem(name: "path", value: file.path),
    ]
    return parts.url!
  }
  func position(for link: CellLink) throws -> (row: Int, column: Int) {
    guard link.document == id else { throw TableError.wrongDocument }
    guard let r = rows.firstIndex(where: { $0.id == link.row }),
      let c = columns.firstIndex(where: { $0.id == link.column })
    else { throw TableError.missingCell }
    return (r, c)
  }
}
struct CellLink {
  let document: UUID
  let row: UUID
  let column: UUID
  let path: String
  init(_ url: URL) throws {
    guard url.scheme == tablinURLScheme, url.host == "open",
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw TableError.invalidLink }
    let items = parts.queryItems ?? []
    func value(_ name: String) -> String? {
      let matches = items.filter { $0.name == name }
      return matches.count == 1 ? matches[0].value : nil
    }
    guard let d = value("document").flatMap(UUID.init(uuidString:)),
      let r = value("row").flatMap(UUID.init(uuidString:)),
      let c = value("column").flatMap(UUID.init(uuidString:)),
      let p = value("path"), p.hasPrefix("/")
    else { throw TableError.invalidLink }
    document = d
    row = r
    column = c
    path = p
  }
}
enum TableError: LocalizedError {
  case invalidDocument, invalidLink, wrongDocument, missingCell, malformedCSV, missingTable
  var errorDescription: String? {
    switch self {
    case .invalidDocument: return "このTablin文書は形式またはバージョンが不正です。"
    case .invalidLink: return "セルリンクの形式が不正です。"
    case .wrongDocument: return "リンク先とは異なる文書です。元の文書を開いてください。"
    case .missingCell: return "リンク先の行または列は削除されています。"
    case .malformedCSV: return "引用符が不正なCSV/TSVです。"
    case .missingTable: return "Markdownの表が見つかりません。"
    }
  }
}
enum TableText {
  static func delimited(_ matrix: [[String]], separator: Character = ",") -> String {
    matrix.map { row in
      row.map { value in
        if value.contains(separator) || value.contains("\"") || value.contains("\n")
          || value.contains("\r")
        {
          return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
      }.joined(separator: String(separator))
    }.joined(separator: "\n")
  }
  static func parseDelimited(_ text: String, separator: Character = ",") throws -> [[String]] {
    let input = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    let chars = Array(
      input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var closed = false
    var i = 0
    while i < chars.count {
      let char = chars[i]
      if quoted {
        if char == "\"" {
          if i + 1 < chars.count && chars[i + 1] == "\"" {
            field.append("\"")
            i += 1
          } else {
            quoted = false
            closed = true
          }
        } else {
          field.append(char)
        }
      } else if char == separator {
        row.append(field)
        field = ""
        closed = false
      } else if char == "\n" {
        row.append(field)
        rows.append(row)
        row = []
        field = ""
        closed = false
      } else if char == "\"" {
        guard field.isEmpty, !closed else { throw TableError.malformedCSV }
        quoted = true
      } else {
        guard !closed else { throw TableError.malformedCSV }
        field.append(char)
      }
      i += 1
    }
    guard !quoted else { throw TableError.malformedCSV }
    if chars.last != "\n" || !row.isEmpty || !field.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows.isEmpty ? [[""]] : rows
  }
  static func markdown(_ matrix: [[String]]) -> String {
    func line(_ row: [String]) -> String {
      "| "
        + row.map {
          $0.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\\", with: "&#92;").replacingOccurrences(
              of: "|", with: "&#124;"
            )
            .replacingOccurrences(of: "\n", with: "<br>")
        }.joined(separator: " | ") + " |"
    }
    guard let first = matrix.first else { return "" }
    return ([line(first), line(first.map { _ in "---" })] + matrix.dropFirst().map(line)).joined(
      separator: "\n")
  }
  static func parseMarkdown(_ text: String) throws -> [[String]] {
    func split(_ line: String) -> [String] {
      var s = line.trimmingCharacters(in: .whitespaces)
      if s.hasPrefix("|") { s.removeFirst() }
      if s.hasSuffix("|") { s.removeLast() }
      var fields: [String] = []
      var field = ""
      var escaped = false
      for c in s {
        if escaped {
          if c != "|" && c != "\\" { field.append("\\") }
          field.append(c)
          escaped = false
        } else if c == "\\" {
          escaped = true
        } else if c == "|" {
          fields.append(field.trimmingCharacters(in: .whitespaces))
          field = ""
        } else {
          field.append(c)
        }
      }
      if escaped { field.append("\\") }
      fields.append(field.trimmingCharacters(in: .whitespaces))
      return fields
    }
    let lines = text.components(separatedBy: .newlines)
    guard lines.count > 1 else { throw TableError.missingTable }
    for i in 1..<lines.count {
      let divider = split(lines[i])
      if !lines[i - 1].contains("|") || divider.isEmpty
        || !divider.allSatisfy({
          $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil
        })
      {
        continue
      }
      var matrix = [split(lines[i - 1])]
      var j = i + 1
      while j < lines.count && lines[j].contains("|")
        && !lines[j].trimmingCharacters(in: .whitespaces).isEmpty
      {
        matrix.append(split(lines[j]))
        j += 1
      }
      return matrix.map {
        $0.map {
          $0.replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(
              of: "<br>", with: "\n"
            )
            .replacingOccurrences(of: "&#124;", with: "|").replacingOccurrences(
              of: "&#92;", with: "\\"
            )
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        }
      }
    }
    throw TableError.missingTable
  }
}
