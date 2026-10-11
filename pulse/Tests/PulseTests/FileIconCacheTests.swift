import AppKit
import Foundation
import Testing
@testable import Pulse

struct FileIconCacheTests {
    @Test @MainActor func iconLookupRunsOffMainThreadAndCachesThumbnail() async {
        let path = "/pulse-icon-test-\(UUID().uuidString).app"
        let image = await FileIconCache.loadIcon(forPath: path) { _ in
            #expect(!Thread.isMainThread)
            return NSImage(size: NSSize(width: 512, height: 512))
        }
        #expect(image.size == NSSize(width: 32, height: 32))
        let cached = await FileIconCache.loadIcon(forPath: path) { _ in
            Issue.record("Cached icon must not trigger another lookup")
            return NSImage(size: .zero)
        }
        #expect(cached === image)
    }
}
