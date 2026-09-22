import Foundation

/// Result of a recording session.
struct RecordingResult {
    let mixPath: URL
    let appPath: URL?
    let micPath: URL?
    let micDelay: TimeInterval
    /// Wall-clock time recording started, captured directly in `start()`.
    /// Not derived from `systemUptime` (which doesn't advance during sleep, so
    /// a meeting spanning a sleep would skew the anchor) — this is exact.
    let recordingStartDate: Date
    var micMute: MicMuteTimeline?
}
