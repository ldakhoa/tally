import Foundation

/// Splits an assistant reply into plain Markdown text and pipe tables, so the chat can lay
/// tables out as real grids instead of showing the raw `| a | b |` source.
public enum AssistantMessageBlock: Hashable, Sendable {
    case text(String)
    case table(headers: [String], rows: [[String]])

    public static func parse(_ message: String) -> [AssistantMessageBlock] {
        let lines = message.components(separatedBy: "\n")
        var blocks: [AssistantMessageBlock] = []
        var textLines: [String] = []

        func flushText() {
            // Blank lines next to a table are spacing the table view already provides.
            while let first = textLines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.removeFirst()
            }
            while let last = textLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.removeLast()
            }
            if !textLines.isEmpty { blocks.append(.text(textLines.joined(separator: "\n"))) }
            textLines = []
        }

        var index = 0
        while index < lines.count {
            if index + 1 < lines.count,
               let headers = cells(in: lines[index]),
               let columnCount = separatorColumnCount(lines[index + 1]),
               columnCount == headers.count {
                var rows: [[String]] = []
                var next = index + 2
                while next < lines.count, let row = cells(in: lines[next]) {
                    var padded = Array(row.prefix(headers.count))
                    padded += Array(repeating: "", count: headers.count - padded.count)
                    rows.append(padded)
                    next += 1
                }
                flushText()
                blocks.append(.table(headers: headers, rows: rows))
                index = next
            } else {
                textLines.append(lines[index])
                index += 1
            }
        }
        flushText()
        return blocks
    }

    /// The cells of one table line, or nil when the line is not a table row.
    static func cells(in line: String) -> [String]? {
        var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
        guard trimmed.contains("|") else { return nil }
        if trimmed.hasPrefix("|") { trimmed = trimmed.dropFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed = trimmed.dropLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                // `\|` is a literal pipe; any other escape is left for the inline Markdown pass.
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// Number of columns in a `|---|:---:|` separator line, or nil when the line is not one.
    static func separatorColumnCount(_ line: String) -> Int? {
        guard line.contains("-"), let cells = cells(in: line) else { return nil }
        for cell in cells {
            var dashes = Substring(cell)
            if dashes.hasPrefix(":") { dashes = dashes.dropFirst() }
            if dashes.hasSuffix(":") { dashes = dashes.dropLast() }
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
        }
        return cells.count
    }
}
