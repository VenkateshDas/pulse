import Foundation
import PulseKit

public struct CLIOutput: Sendable {
    public let isJSON: Bool
    public let isTTY: Bool

    public init(isJSON: Bool = false) {
        self.isJSON = isJSON
        self.isTTY = isatty(STDOUT_FILENO) == 1
    }

    // MARK: - JSON Output

    public func emitJSON<T: Encodable>(_ value: T) {
        do {
            print(try Self.json(value))
        } catch {
            fputs("error: JSON encoding failed: \(error)\n", stderr)
            exit(1)
        }
    }

    public static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    public static func bytes(_ value: Int64) -> String {
        (value < 0 ? "-" : "") + ByteFormat.string(value.magnitude)
    }

    // MARK: - ANSI Color Helpers

    public func style(_ text: String, code: String) -> String {
        guard isTTY && !isJSON else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }

    public func bold(_ text: String) -> String { style(text, code: "1") }
    public func dim(_ text: String) -> String { style(text, code: "2") }
    public func green(_ text: String) -> String { style(text, code: "32") }
    public func yellow(_ text: String) -> String { style(text, code: "33") }
    public func red(_ text: String) -> String { style(text, code: "31") }
    public func cyan(_ text: String) -> String { style(text, code: "36") }
    public func blue(_ text: String) -> String { style(text, code: "34") }

    // MARK: - Formatted Output

    public func printHeader(_ title: String) {
        guard !isJSON else { return }
        print("\n" + bold(cyan("=== \(title) ===")))
    }

    public func printRow(label: String, value: String, indent: Int = 2) {
        guard !isJSON else { return }
        let padding = String(repeating: " ", count: indent)
        let formattedLabel = dim(label.padding(toLength: 20, withPad: " ", startingAt: 0))
        print("\(padding)\(formattedLabel) : \(value)")
    }

    public func printError(_ message: String) {
        if isJSON {
            let errObj = ["error": message]
            emitJSON(errObj)
        } else {
            fputs("\(red("error:")) \(message)\n", stderr)
        }
    }

    public func printSuccess(_ message: String) {
        guard !isJSON else { return }
        print("\(green("✓")) \(message)")
    }

    public func printWarning(_ message: String) {
        guard !isJSON else { return }
        print("\(yellow("!")) \(message)")
    }

}
