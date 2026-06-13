import Foundation

func rawFreeBytes() -> UInt64 {
    let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return UInt64(values?.volumeAvailableCapacity ?? 0)
}

func purgeableBytes() -> UInt64 {
    let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
    guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return 0 }
    let finder = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
    let raw = UInt64(values.volumeAvailableCapacity ?? 0)
    return finder > raw ? finder - raw : 0
}

print("Before: Raw Free = \(rawFreeBytes() / 1_000_000) MB, Purgeable = \(purgeableBytes() / 1_000_000) MB")

let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
FileManager.default.createFile(atPath: tempURL.path, contents: nil)
let fd = open(tempURL.path, O_RDWR)
if fd == -1 {
    print("Failed to open file")
    exit(1)
}

var totalAllocated: UInt64 = 0
let chunkSize: Int64 = 1024 * 1024 * 1024 // 1 GB chunks

while true {
    var store = fstore_t(
        fst_flags: UInt32(F_ALLOCATEALL),
        fst_posmode: F_PEOFPOSMODE,
        fst_offset: 0,
        fst_length: chunkSize,
        fst_bytesalloc: 0
    )
    let result = fcntl(fd, F_PREALLOCATE, &store)
    if result == -1 {
        print("fcntl failed: \(String(cString: strerror(errno)))")
        break
    }
    totalAllocated += UInt64(chunkSize)
    print("Allocated \(totalAllocated / 1_000_000) MB...")
    ftruncate(fd, Int64(totalAllocated))
}

print("Sleeping 2 seconds to let OS purge...")
sleep(2)

print("During: Raw Free = \(rawFreeBytes() / 1_000_000) MB, Purgeable = \(purgeableBytes() / 1_000_000) MB")

close(fd)
try? FileManager.default.removeItem(at: tempURL)
print("Cleaned up dummy file.")

print("After: Raw Free = \(rawFreeBytes() / 1_000_000) MB, Purgeable = \(purgeableBytes() / 1_000_000) MB")
