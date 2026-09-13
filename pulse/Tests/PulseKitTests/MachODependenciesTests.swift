import Foundation
import Testing
@testable import PulseKit

@Suite("Native Mach-O dependencies")
struct MachODependenciesTests {
    private func word(_ value: UInt64, bytes: Int = 4, little: Bool) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ((little ? $0 : bytes - 1 - $0) * 8)) })
    }
    private func image(path: String, little: Bool, wide: Bool, kind: UInt64 = 0xc) -> Data {
        let name = Data(path.utf8) + Data([0])
        let commandSize = (24 + name.count + 7) / 8 * 8
        var header = [wide ? UInt64(0xfeedfacf) : 0xfeedface, 0, 0, 2, 1, UInt64(commandSize), 0]
        if wide { header.append(0) }
        var data = header.reduce(into: Data()) { $0 += word($1, little: little) }
        data += [kind, UInt64(commandSize), 24, 0, 0, 0].reduce(into: Data()) { $0 += word($1, little: little) }
        data += name
        data += Data(repeating: 0, count: commandSize - 24 - name.count)
        return data
    }
    private func read(_ data: Data) throws -> [String] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-macho-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        return MachODependencies.paths(in: url)
    }
    @Test(arguments: [true, false]) func thinByteOrders(little: Bool) throws {
        for wide in [true, false] {
            for kind: UInt64 in [0xc, 0x80000018, 0x8000001f, 0x20, 0x80000023] {
                #expect(try read(image(path: "/opt/example/lib.dylib", little: little, wide: wide, kind: kind)) == ["/opt/example/lib.dylib"])
            }
            #expect(try read(image(path: "/self.dylib", little: little, wide: wide, kind: 0xd)).isEmpty)
        }
    }
    @Test(arguments: [true, false]) func universalByteOrders(little: Bool) throws {
        for wide in [true, false] {
            let thin = image(path: "/usr/lib/example.dylib", little: true, wide: true)
            let offset: UInt64 = wide ? 40 : 28
            var data = word(wide ? 0xcafebabf : 0xcafebabe, little: little) + word(1, little: little)
            data += word(0, little: little) + word(0, little: little)
            data += word(offset, bytes: wide ? 8 : 4, little: little)
            data += word(UInt64(thin.count), bytes: wide ? 8 : 4, little: little)
            data += word(0, little: little)
            if wide { data += word(0, little: little) }
            #expect(try read(data + thin) == ["/usr/lib/example.dylib"])
        }
    }
    @Test func truncatedAndMalformedNeverProduceEdges() throws {
        let valid = image(path: "/usr/lib/example.dylib", little: true, wide: true)
        for end in 0..<valid.count { #expect(try read(Data(valid.prefix(end))).isEmpty) }
        for (offset, value) in [(20, UInt64.max), (36, 0), (40, UInt64.max)] {
            var malformed = valid
            malformed.replaceSubrange(offset..<offset+4, with: word(value, little: true))
            #expect(try read(malformed).isEmpty)
        }
        #expect(try read(Data("#!/bin/sh\nexit 99\n".utf8)).isEmpty)
        #expect(try read(image(path: "@rpath/unresolved.dylib", little: true, wide: true)).isEmpty)
    }
    @Test func loaderRelativePathUsesInspectedDirectory() throws {
        let paths = try read(image(path: "@loader_path/lib/example.dylib", little: true, wide: true))
        #expect(paths.first?.hasSuffix("/lib/example.dylib") == true)
        #expect(try read(image(path: "@loader_path/", little: true, wide: true)).count == 1)
    }
    @Test func realSystemBinaryHasNativeDependencies() {
        #expect(!MachODependencies.paths(in: URL(fileURLWithPath: "/bin/ls")).isEmpty)
    }
}
