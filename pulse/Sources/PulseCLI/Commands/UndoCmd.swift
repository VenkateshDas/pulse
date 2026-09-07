import Foundation
import PulseKit

public struct UndoEntryDTO: Codable, Sendable {
    public let id: String
    public let op: String
    public let date: Date
    public let itemCount: Int
    public let bytesFreed: Int64
    public let bytesFreedFormatted: String

    public init(entry: UndoEntry) {
        self.id = entry.id.uuidString
        self.op = entry.op
        self.date = entry.date
        self.itemCount = entry.items.count
        self.bytesFreed = entry.bytesFreed
        self.bytesFreedFormatted = CLIOutput.bytes(entry.bytesFreed)
    }
}

public enum UndoCmd {
    public static func run(parser: CLIParser, output: CLIOutput) async {
        let action = parser.positional.first?.lowercased() ?? "list"
        let journal = UndoJournal.shared
        let allEntries: [UndoEntry]
        do { allEntries = try await journal.snapshot() }
        catch { output.printError(error.localizedDescription); exit(1) }

        if action == "list" || action.isEmpty {
            let entries = allEntries.map { UndoEntryDTO(entry: $0) }

            if output.isJSON {
                output.emitJSON(entries)
            } else {
                output.printHeader("Undo Journal (Recent Deletions)")
                if entries.isEmpty {
                    print("  \(output.green("✓")) Undo journal is empty. No recent deletions recorded.")
                } else {
                    let fmt = DateFormatter()
                    fmt.dateStyle = .short
                    fmt.timeStyle = .short
                    for e in entries {
                        let dateStr = fmt.string(from: e.date)
                        print("  • [\(output.cyan(String(e.id.prefix(8))))] \(output.bold(e.op)) — \(e.bytesFreedFormatted) (\(e.itemCount) items) on \(dateStr)")
                    }
                    print("\n" + output.dim("To restore an operation: pulse undo restore <id>"))
                }
            }
            return
        }

        if action == "restore" {
            guard let idStr = parser.positional.dropFirst().first else {
                output.printError("Missing entry ID to restore. Usage: pulse undo restore <id>")
                exit(2)
            }

            let matches = allEntries.filter { $0.id.uuidString.lowercased().hasPrefix(idStr.lowercased()) }
            guard matches.count == 1, let matched = matches.first else {
                output.printError("Undo ID missing or ambiguous; use the full ID from undo list")
                exit(1)
            }

            do {
                let restoredCount = try await journal.restore(matched.id)
                let remaining = try await journal.snapshot().first { $0.id == matched.id }?.items.count ?? 0
                struct Result: Encodable { let entryID: UUID; let restoredItems: Int; let remainingItems: Int; let unavailableItems: Int }

                if output.isJSON {
                    output.emitJSON(Result(entryID: matched.id, restoredItems: restoredCount, remainingItems: remaining, unavailableItems: max(0, matched.items.count - restoredCount - remaining)))
                } else {
                    output.printSuccess("Restored \(restoredCount) item(s) from operation: \(output.bold(matched.op))")
                }
                if remaining > 0 || restoredCount != matched.items.count { exit(1) }
            } catch {
                output.printError("Failed to restore entry: \(error.localizedDescription)")
                exit(1)
            }
            return
        }

        output.printError("Unknown undo action '\(action)'. Use 'list' or 'restore <id>'.")
        exit(2)
    }
}
