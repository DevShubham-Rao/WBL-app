import Foundation
import ZIPFoundation

// Reads standard .xlsx workbooks exported from Google Sheets or Microsoft Excel.
// The first worksheet is imported. Shared strings and inline strings are supported.
enum SpreadsheetImport {
    enum Failure: LocalizedError {
        case missingSheet, invalidFile
        var errorDescription: String? {
            switch self {
            case .missingSheet: return "The spreadsheet has no readable first worksheet."
            case .invalidFile: return "The selected file is not a valid Excel spreadsheet."
            }
        }
    }

    static func students(from url: URL) throws -> [Student] {
        guard let archive = Archive(url: url, accessMode: .read) else { throw Failure.invalidFile }
        func data(_ path: String) throws -> Data? {
            guard let entry = archive[path] else { return nil }
            var bytes = Data()
            _ = try archive.extract(entry) { bytes.append($0) }
            return bytes
        }
        var strings: [String] = []
        if let raw = try data("xl/sharedStrings.xml") {
            let p = XMLCells(kind: .strings); p.parse(raw); strings = p.sharedStrings
        }
        // Follow workbook relationships so the first sheet need not be sheet1.xml.
        var sheetPath = "xl/worksheets/sheet1.xml"
        if let book = try data("xl/workbook.xml"), let rel = try data("xl/_rels/workbook.xml.rels") {
            let workbook = XMLCells(kind: .workbook); workbook.parse(book)
            let relations = XMLCells(kind: .relationships); relations.parse(rel)
            if let id = workbook.firstSheetRelationship, let target = relations.rels[id] {
                let normalized = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
                sheetPath = (normalized as NSString).standardizingPath
            }
        }
        guard let sheet = try data(sheetPath) else { throw Failure.missingSheet }
        let parser = XMLCells(kind: .sheet, sharedStrings: strings)
        parser.parse(sheet)
        return CSVImport.students(fromRows: parser.rows)
    }
}

private final class XMLCells: NSObject, XMLParserDelegate {
    enum Kind { case strings, sheet, workbook, relationships }
    let kind: Kind
    let sharedValues: [String]
    var sharedStrings: [String] = []
    var rows: [[String]] = []
    var rels: [String:String] = [:]
    var firstSheetRelationship: String?
    private var inString = false
    private var inValue = false
    private var currentString = ""
    private var currentValue = ""
    private var currentRow: [Int:String] = [:]
    private var column = 0
    private var cellType = ""
    init(kind: Kind, sharedStrings: [String] = []) { self.kind = kind; self.sharedValues = sharedStrings }
    func parse(_ data: Data) { let parser = XMLParser(data: data); parser.delegate = self; _ = parser.parse() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.components(separatedBy: ":").last ?? elementName
        switch kind {
        case .workbook:
            if name == "sheet" && firstSheetRelationship == nil { firstSheetRelationship = attributeDict["r:id"] ?? attributeDict["id"] }
        case .relationships:
            if name == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] { rels[id] = target }
        case .strings:
            if name == "si" { inString = true; currentString = "" }
            if name == "t" { inValue = true }
        case .sheet:
            if name == "row" { currentRow = [:] }
            if name == "c" {
                cellType = attributeDict["t"] ?? ""
                currentValue = ""
                let ref = attributeDict["r"] ?? "A1"
                var col = 0
                for c in ref.uppercased() { guard let ascii = c.asciiValue, ascii >= 65 && ascii <= 90 else { break }; col = col * 26 + Int(ascii - 64) }
                column = max(0, col - 1)
            }
            if name == "v" || name == "t" { inValue = true }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { currentValue += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.components(separatedBy: ":").last ?? elementName
        switch kind {
        case .strings:
            if name == "t" { currentString += currentValue; currentValue = ""; inValue = false }
            if name == "si" { sharedStrings.append(currentString); inString = false }
        case .sheet:
            if name == "v" || name == "t" { inValue = false }
            if name == "c" {
                var value = currentValue
                if cellType == "s", let index = Int(value), sharedValues.indices.contains(index) { value = sharedValues[index] }
                if cellType != "e" { currentRow[column] = value }
            }
            if name == "row", let maxCol = currentRow.keys.max(), maxCol < 250 {
                var row = Array(repeating: "", count: maxCol + 1)
                for (i, value) in currentRow { row[i] = value }
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            }
        default: break
        }
    }
}
