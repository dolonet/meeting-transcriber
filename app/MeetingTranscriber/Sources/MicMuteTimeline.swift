import Foundation

/// Observations are on the raw microphone file clock, before micDelaySeconds.
/// Absence, stale samples and unsupported controls never imply unmuted.
struct MicMuteTimeline: Codable, Sendable {
    enum State: String, Codable, Sendable { case muted, unmuted, unknown }
    struct Observation: Codable, Sendable {
        let timeSeconds: Double
        let state: State
    }

    let schemaVersion: Int
    let clock: String
    let bundleID: String
    let observations: [Observation]

    init(bundleID: String, observations: [Observation] = []) {
        schemaVersion = 1
        clock = "microphone-seconds"
        self.bundleID = bundleID
        self.observations = observations
    }

    static func state(bundleID: String, role: String, identifier: String, value: String) -> State {
        if bundleID == "ru.yandex.desktop.telemost", role == "AXCheckBox",
           identifier.hasSuffix("MainConferenceView.ControlPanelWidget.microphoneButton") {
            return value == "0" ? .unmuted : value == "1" ? .muted : .unknown
        }
        if bundleID == "us.zoom.xos", role == "AXMenuItem", identifier == "onMuteAudio:" {
            switch value {
            case "Mute audio", "Выключить звук": return .unmuted
            case "Unmute audio", "Включить звук": return .muted
            default: return .unknown
            }
        }
        return .unknown
    }
}
