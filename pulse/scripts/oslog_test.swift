import Foundation
import OSLog

func fetchOSLog() {
    do {
        let store = try OSLogStore(scope: .system)
        let position = store.position(date: Date().addingTimeInterval(-3600)) // last hour
        // We want sleep/wake or power events
        let predicate = NSPredicate(format: "subsystem == 'com.apple.PowerManagement' OR subsystem == 'com.apple.powerlog'")
        let entries = try store.getEntries(with: [], at: position, matching: predicate)
        
        var count = 0
        for entry in entries {
            if let log = entry as? OSLogEntryLog {
                print("\(log.date) | \(log.subsystem): \(log.composedMessage)")
                count += 1
                if count > 20 { break }
            }
        }
    } catch {
        print("Error: \(error)")
    }
}
fetchOSLog()
