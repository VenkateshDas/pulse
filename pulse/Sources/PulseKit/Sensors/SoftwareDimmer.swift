import Cocoa
import CoreGraphics

public class SoftwareDimmer: @unchecked Sendable {
    public static let shared = SoftwareDimmer()
    
    private init() {
        Task { @MainActor in
            setupScreenObserver()
        }
    }
    
    // MARK: - Overlay Window Management
    
    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]
    
    @MainActor
    private func setupScreenObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pruneStaleOverlays()
            }
        }
    }
    
    @MainActor
    private func pruneStaleOverlays() {
        let activeIDs = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }
        for (id, window) in overlayWindows {
            if !activeIDs.contains(id) {
                window.close()
                overlayWindows.removeValue(forKey: id)
            }
        }
    }
    
    // MARK: - API
    
    @MainActor
    public func setBrightness(for displayID: CGDirectDisplayID, brightness: Double) {
        applyOverlayDimming(for: displayID, brightness: brightness)
    }
    
    @MainActor
    private func applyOverlayDimming(for displayID: CGDirectDisplayID, brightness: Double) {
        var window: NSWindow
        if let existing = self.overlayWindows[displayID] {
            window = existing
        } else {
            guard let screen = NSScreen.screens.first(where: {
                guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                return id == displayID
            }) else {
                return
            }
            
            window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            
            // ARC owns this window via `overlayWindows`. The AppKit default
            // (isReleasedWhenClosed = true) makes close() ALSO release it —
            // pruneStaleOverlays' close() then over-released and crashed the
            // app the moment an external display was unplugged.
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .init(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            
            let view = NSView(frame: window.contentRect(forFrameRect: screen.frame))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.alphaValue = 0.0
            
            window.contentView = view
            window.orderFront(nil)
            
            self.overlayWindows[displayID] = window
        }
        
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }) {
            window.setFrame(screen.frame, display: true)
        }
        
        let alpha = CGFloat(1.0 - brightness) * 0.85
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.contentView?.animator().alphaValue = alpha
        }
    }
}
