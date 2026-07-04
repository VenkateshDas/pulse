import AppKit
import SwiftUI

/// Native-style on-screen HUD shown whenever brightness changes through
/// Pulse — the app's own slider, physical media keys, or DDC on an
/// external monitor. macOS's own OSD never fires for these paths (media
/// keys are consumed before the system sees them; DDC changes on an
/// external monitor are invisible to macOS entirely), so this recreates
/// the look of the current-generation macOS brightness HUD: a glass pill
/// docked top-right under the menu bar, showing the display name and
/// percentage above a bar. Modeled on Lunar's `Mac26BrightnessOSDView`
/// (github.com/alin23/lunar, MIT).
@MainActor
public final class BrightnessOSD {
    public static let shared = BrightnessOSD()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<BrightnessOSDView>?
    private var currentDisplayID: CGDirectDisplayID?
    private var hideWorkItem: DispatchWorkItem?

    private static let size = CGSize(width: 290, height: 62)
    /// Gap between the pill's top edge and the bottom of the menu bar,
    /// matching the real HUD's docked position.
    private static let topInset: CGFloat = 10
    private static let hideDelay: TimeInterval = 1.6

    private init() {}

    /// `fraction` is 0...1 — same normalization the app's own slider uses.
    public func show(fraction: Double, on displayID: CGDirectDisplayID) {
        let screen = Self.screen(for: displayID)
        let panel = panelForScreen(screen, displayID: displayID)
        let name = screen.map(Self.displayName) ?? "Display"
        hostingView?.rootView = BrightnessOSDView(fraction: fraction, displayName: name)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: workItem)
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Fully off screen once faded — an invisible shielding-level
            // panel left ordered-in can swallow the AX click routing the
            // macOS menu bar uses (see SoftwareDimmer).
            if self?.panel?.alphaValue == 0 {
                self?.panel?.orderOut(nil)
            }
        })
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main
    }

    private static func displayName(for screen: NSScreen) -> String {
        if #available(macOS 12.0, *) {
            return screen.localizedName
        }
        return "Display"
    }

    private func panelForScreen(_ screen: NSScreen?, displayID: CGDirectDisplayID) -> NSPanel {
        if let panel, currentDisplayID == displayID {
            reposition(panel, on: screen)
            return panel
        }

        let hosting = NSHostingView(rootView: BrightnessOSDView(fraction: 0, displayName: ""))
        hosting.frame = CGRect(origin: .zero, size: Self.size)

        let newPanel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // ARC owns this panel; never let close() double-release it.
        newPanel.isReleasedWhenClosed = false
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.ignoresMouseEvents = true
        newPanel.isMovableByWindowBackground = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Same level SoftwareDimmer uses — visible above full-screen apps
        // and video, matching where the real brightness HUD shows.
        newPanel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newPanel.contentView = hosting

        reposition(newPanel, on: screen)

        panel?.orderOut(nil)
        panel = newPanel
        hostingView = hosting
        currentDisplayID = displayID
        return newPanel
    }

    /// Top-right, docked just under the menu bar — `visibleFrame` already
    /// excludes it, so this sits flush below with a small gap.
    private func reposition(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.maxX - Self.size.width - 20,
            y: visible.maxY - Self.size.height - Self.topInset
        )
        panel.setFrameOrigin(origin)
    }
}

struct BrightnessOSDView: View {
    let fraction: Double
    let displayName: String

    private var clamped: Double { max(0, min(1, fraction)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                        .frame(height: 6)
                    GeometryReader { geo in
                        let width = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(6, width * clamped), height: 6)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .offset(x: max(0, width * clamped - 7))
                        }
                        .frame(height: 14)
                    }
                    .frame(height: 14)
                }
                .frame(height: 14)
                Image(systemName: "sun.max.fill")
            }
            .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(width: 290, height: 62, alignment: .center)
        .background(VisualEffectBlur())
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .preferredColorScheme(.dark)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
