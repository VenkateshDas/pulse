import Foundation

func purgeableBytes() -> UInt64 {
    let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
    guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return 0 }
    let finder = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
    let raw = UInt64(values.volumeAvailableCapacity ?? 0)
    return finder > raw ? finder - raw : 0
}

print("Purgeable before: \(purgeableBytes() / 1_000_000) MB")

let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
FileManager.default.createFile(atPath: tempURL.path, contents: nil)
let fd = open(tempURL.path, O_RDWR)
if fd == -1 {
    print("Failed to open file")
    exit(1)
}

// INSTANT UNLINK - GUARANTEES SAFE CLEANUP EVEN ON CRASH!
unlink(tempURL.path)
print("File unlinked. Writing until ENOSPC...")

let bufferSize = 10 * 1024 * 1024 // 10MB
let buffer = [UInt8](repeating: 0, count: bufferSize)

var totalWritten: UInt64 = 0
while true {
    let bytesWritten = write(fd, buffer, bufferSize)
    if bytesWritten < 0 {
        print("Write failed: \(String(cString: strerror(errno)))")
        break
    }
    totalWritten += UInt64(bytesWritten)
}

print("Total written: \(totalWritten / 1_000_000_000) GB")
print("Sleeping 2 seconds for OS purge...")
sleep(2)

print("Purgeable during: \(purgeableBytes() / 1_000_000) MB")

close(fd)
print("Purgeable after close: \(purgeableBytes() / 1_000_000) MB")
