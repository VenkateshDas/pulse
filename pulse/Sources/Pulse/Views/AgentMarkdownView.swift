import SwiftUI

enum AgentMarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case code(String)
    case table([String], [[String]])
    case quote(String)
    case rule
}

enum AgentMarkdownParser {
    static func parse(_ source: String) -> [AgentMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [AgentMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { index += 1; continue }

            if line.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(code.joined(separator: "\n")))
            } else if let heading = heading(line) {
                blocks.append(.heading(heading.level, heading.text)); index += 1
            } else if index + 1 < lines.count, isTableDivider(lines[index + 1]), line.contains("|") {
                let headers = cells(line); index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[index])); index += 1
                }
                blocks.append(.table(headers, rows))
            } else if let item = bullet(line) {
                var values = [item]; index += 1
                while index < lines.count, let next = bullet(lines[index].trimmingCharacters(in: .whitespaces)) {
                    values.append(next); index += 1
                }
                blocks.append(.bullets(values))
            } else if let item = numbered(line) {
                var values = [item]; index += 1
                while index < lines.count, let next = numbered(lines[index].trimmingCharacters(in: .whitespaces)) {
                    values.append(next); index += 1
                }
                blocks.append(.numbered(values))
            } else if line.hasPrefix(">") {
                blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); index += 1
            } else if line == "---" || line == "***" {
                blocks.append(.rule); index += 1
            } else {
                var paragraph = [line]; index += 1
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty || startsBlock(lines, at: index) { break }
                    paragraph.append(next); index += 1
                }
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
            }
        }
        return blocks
    }

    private static func startsBlock(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("```") || heading(line) != nil || bullet(line) != nil || numbered(line) != nil ||
            line.hasPrefix(">") || line == "---" || line == "***" ||
            (index + 1 < lines.count && line.contains("|") && isTableDivider(lines[index + 1]))
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func bullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2))
    }

    private static func numbered(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), !line[..<dot].isEmpty,
              line[..<dot].allSatisfy(\.isNumber), line[line.index(after: dot)...].first == " " else { return nil }
        return String(line[line.index(dot, offsetBy: 2)...])
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy {
            let value = $0.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "")
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

struct AgentMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(AgentMarkdownParser.parse(source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder private func blockView(_ block: AgentMarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text).font(.system(size: level == 1 ? 21 : level == 2 ? 18 : 15, weight: .bold))
                .padding(.top, level < 3 ? 4 : 0)
        case let .paragraph(text):
            inline(text).font(.system(size: 14)).lineSpacing(3)
        case let .bullets(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundStyle(Halo.interactive); inline(item) }
                }
            }.font(.system(size: 14))
        case let .numbered(items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(index + 1).").foregroundStyle(Halo.textDim); inline(item) }
                }
            }.font(.system(size: 14))
        case let .code(code):
            Text(code).font(.system(size: 11, design: .monospaced)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Halo.surface2, in: RoundedRectangle(cornerRadius: Halo.Radius.small))
        case let .table(headers, rows):
            table(headers: headers, rows: rows)
        case let .quote(text):
            inline(text).font(.system(size: 13)).foregroundStyle(Halo.textSecondary).padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Halo.interactive).frame(width: 2) }
        case .rule:
            Divider().overlay(Halo.borderSubtle)
        }
    }

    private func inline(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return Text((try? AttributedString(markdown: source, options: options)) ?? AttributedString(source))
    }

    private func table(headers: [String], rows: [[String]]) -> some View {
        let count = max(headers.count, rows.map(\.count).max() ?? 0)
        return VStack(spacing: 0) {
            tableRow(headers, count: count, header: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(Halo.borderSubtle)
                tableRow(row, count: count, header: false)
            }
        }
        .background(Halo.surface1, in: RoundedRectangle(cornerRadius: Halo.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: Halo.Radius.small).stroke(Halo.borderSubtle))
    }

    private func tableRow(_ cells: [String], count: Int, header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                inline(index < cells.count ? cells[index] : "")
                    .font(.system(size: 11, weight: header ? .semibold : .regular, design: header ? .default : .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(header ? Halo.surface2 : Color.clear)
    }
}
