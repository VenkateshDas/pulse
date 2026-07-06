import AppKit

/// Finder's own trash sounds, so Pulse's trash operations feel native.
/// Instances are cached: NSSound plays asynchronously and must stay retained.
@MainActor
enum TrashSound {
    private static let finderSounds =
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/"
    private static let move = NSSound(contentsOfFile: finderSounds + "move to trash.aif", byReference: true)
    private static let empty = NSSound(contentsOfFile: finderSounds + "empty trash.aif", byReference: true)

    static func moveToTrash() {
        move?.stop()
        move?.play()
    }

    static func emptyTrash() {
        empty?.stop()
        empty?.play()
    }
}
