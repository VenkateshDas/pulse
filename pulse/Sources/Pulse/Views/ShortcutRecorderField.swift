import AppKit
import PulseKit
import SwiftUI

/// Click-to-record shortcut field: click to enter "Recording…", press a key
/// chord (must include a modifier) to bind it. Standard macOS
/// shortcut-recorder pattern (Alfred, Rectangle, etc).
struct ShortcutRecorderField: View {
    let combo: KeyCombo
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onCapture: (NSEvent) -> Void

    var body: some View {
        Button {
            onStartRecording()
        } label: {
            Text(isRecording ? "Recording…" : combo.displayString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Halo.ion : Halo.textPrimary)
                .frame(minWidth: 110)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Halo.surface2, in: RoundedRectangle(cornerRadius: Halo.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(KeyCaptureView(isActive: isRecording, onCapture: onCapture))
    }
}

/// Invisible NSViewRepresentable that installs a local key-down monitor only
/// while `isActive`, so recording never intercepts keys outside this field.
private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onCapture: onCapture)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var monitor: Any?

        func update(isActive: Bool, onCapture: @escaping (NSEvent) -> Void) {
            if isActive, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    onCapture(event)
                    return nil
                }
            } else if !isActive, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
