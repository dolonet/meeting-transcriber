import Foundation

/// Tracks an audio track's position on a wall-clock timeline anchored to its
/// first captured buffer, so a device-change restart gap becomes silence and the
/// track stays aligned to real time (issue #379 follow-up).
///
/// The capture handler feeds each buffer's *hardware* host-time (jitter-free
/// presentation time, e.g. `AVAudioTime.hostTime` or `AudioTimeStamp.mHostTime`,
/// converted to seconds) and its frame count; the anchor returns how many silent
/// frames to write before that buffer. Using the hardware timestamp — not the
/// callback wall-clock — means continuous capture inserts nothing (the timestamp
/// advances exactly with the audio), while a restart gap, where the timestamp
/// jumps forward, is filled precisely.
///
/// Survives restarts: it is anchored once on the first buffer and never reset, so
/// the gap between the last pre-restart buffer and the first post-restart buffer
/// is bridged automatically. Not thread-safe — drive it from the single capture
/// callback context.
struct TimelineAnchor {
    let rate: Int
    private(set) var anchorHostSeconds: Double?
    private var framesWritten = 0
    private(set) var isReliable = true

    /// Only reliable clocks may authorise microphone samples for upload.
    var reliableOriginSeconds: Double? {
        isReliable ? anchorHostSeconds : nil
    }

    /// Gaps beyond this are treated as a corrupt timestamp, not a real device
    /// outage: no silence is inserted (the write would be gigabytes of zeros on
    /// the audio thread, and `AVAudioFrameCount` traps past UInt32.max). The
    /// anchor is absolute, so a one-off glitched buffer self-heals on the next
    /// sane timestamp.
    static let maxGapSeconds: Double = 600

    init(rate: Int) {
        self.rate = rate
    }

    /// Silent frames to insert before a buffer that presents at `hostSeconds`
    /// carrying `frameCount` frames, to keep the written stream aligned to
    /// wall-clock. The first call sets the anchor and inserts nothing. Never
    /// negative — an early/jittered timestamp just appends.
    mutating func silenceFramesBefore(hostSeconds: Double, frameCount: Int) -> Int {
        guard hostSeconds.isFinite, frameCount >= 0 else {
            isReliable = false
            return 0
        }
        guard let anchor = anchorHostSeconds else {
            anchorHostSeconds = hostSeconds
            framesWritten = frameCount
            return 0
        }
        let position = ((hostSeconds - anchor) * Double(rate)).rounded()
        guard position.isFinite, position > Double(Int.min), position < Double(Int.max) else {
            isReliable = false
            framesWritten += frameCount
            return 0
        }
        let expected = Int(position)
        // A large backwards jump cannot be represented by silence padding.
        if position < Double(framesWritten) - 0.25 * Double(rate) { isReliable = false }
        let silence = expected > framesWritten ? expected - framesWritten : 0
        guard silence <= Int(Self.maxGapSeconds * Double(rate)) else {
            isReliable = false
            framesWritten += frameCount
            return 0
        }
        framesWritten += silence + frameCount
        return silence
    }
}
