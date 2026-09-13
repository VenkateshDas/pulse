import Foundation
import MachO

/// Reads load commands only, never loads or executes the inspected image.
enum MachODependencies {
    static func paths(in input: URL) -> [String] {
        let url = input.resolvingSymlinksInPath()
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return [] }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard count >= 0, count <= 1_048_576, offset <= size,
                  UInt64(count) <= size - offset else { return nil }
            do {
                try file.seek(toOffset: offset)
                let data = try file.read(upToCount: count)
                return data?.count == count ? data : nil
            } catch { return nil }
        }
        func number(_ data: Data, _ offset: Int, _ bytes: Int = 4, _ little: Bool = false) -> UInt64 {
            let indices = little ? Array((offset..<offset + bytes).reversed()) : Array(offset..<offset + bytes)
            return indices.reduce(0) { ($0 << 8) | UInt64(data[$1]) }
        }
        func thin(_ offset: UInt64, _ length: UInt64) -> [String] {
            guard length >= 28, let header = read(offset, 28) else { return [] }
            let magic = number(header, 0)
            guard [UInt64(MH_MAGIC), UInt64(MH_CIGAM), UInt64(MH_MAGIC_64), UInt64(MH_CIGAM_64)].contains(magic) else { return [] }
            let little = magic == UInt64(MH_CIGAM) || magic == UInt64(MH_CIGAM_64)
            let headerSize: UInt64 = magic == UInt64(MH_MAGIC_64) || magic == UInt64(MH_CIGAM_64) ? 32 : 28
            let count = number(header, 16, 4, little)
            let commandBytes = number(header, 20, 4, little)
            guard length >= headerSize, commandBytes <= length - headerSize,
                  commandBytes <= 1_048_576, count <= commandBytes / 8,
                  let commands = read(offset + headerSize, Int(commandBytes)) else { return [] }
            let loads: Set<UInt64> = [UInt64(LC_LOAD_DYLIB), UInt64(LC_LOAD_WEAK_DYLIB),
                UInt64(LC_REEXPORT_DYLIB), UInt64(LC_LAZY_LOAD_DYLIB), UInt64(LC_LOAD_UPWARD_DYLIB)]
            var cursor = 0, paths: [String] = []
            for _ in 0..<count {
                guard cursor <= commands.count - 8 else { return [] }
                let kind = number(commands, cursor, 4, little)
                let size = Int(number(commands, cursor + 4, 4, little))
                guard size >= 8, size <= commands.count - cursor else { return [] }
                if loads.contains(kind) {
                    guard size >= 24 else { return [] }
                    let name = Int(number(commands, cursor + 8, 4, little))
                    guard name >= 24, name < size else { return [] }
                    let bytes = commands[(cursor + name)..<(cursor + size)]
                    guard let end = bytes.firstIndex(of: 0),
                          let path = String(data: bytes[..<end], encoding: .utf8) else { return [] }
                    if path.hasPrefix("/") { paths.append(path) }
                    else if path.hasPrefix("@loader_path/") || path.hasPrefix("@executable_path/") {
                        paths.append(url.deletingLastPathComponent().appendingPathComponent(String(path.dropFirst(path.hasPrefix("@loader_path/") ? 13 : 17))).standardizedFileURL.path)
                    }
                }
                cursor += size
            }
            return paths
        }
        guard let header = read(0, 8) else { return [] }
        let magic = number(header, 0)
        let fat64 = magic == UInt64(FAT_MAGIC_64) || magic == UInt64(FAT_CIGAM_64)
        if magic == UInt64(FAT_MAGIC) || magic == UInt64(FAT_CIGAM) || fat64 {
            let little = magic == UInt64(FAT_CIGAM) || magic == UInt64(FAT_CIGAM_64)
            let count = number(header, 4, 4, little)
            let stride = fat64 ? 32 : 20
            guard count <= 64, let arches = read(8, Int(count) * stride) else { return [] }
            var result: [String] = []
            for i in 0..<Int(count) {
                let offset = number(arches, i * stride + 8, fat64 ? 8 : 4, little)
                let length = number(arches, i * stride + (fat64 ? 16 : 12), fat64 ? 8 : 4, little)
                guard offset >= 8 + UInt64(count) * UInt64(stride), offset <= size, length <= size - offset else { continue }
                result += thin(offset, length)
            }
            return Array(Set(result)).sorted()
        }
        return Array(Set(thin(0, size))).sorted()
    }
}
