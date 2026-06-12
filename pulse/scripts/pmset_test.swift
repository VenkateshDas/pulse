import Foundation

func parsePMSetLog() -> [Date: TimeInterval] {
    let task = Process()
    task.launchPath = "/usr/bin/pmset"
    task.arguments = ["-g", "log"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        
        let lines = output.split(separator: "\n")
        var dailyUsage = [Date: TimeInterval]()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var lastDate: Date?
        var lastWasBatt = false
        var lastWasAwake = false
        
        // This is a naive parsing. Let's see if we can do better.
        // We know we want the time difference when it's on battery and awake.
        
    } catch {
        print("Error: \(error)")
    }
    return [:]
}
print(parsePMSetLog())
