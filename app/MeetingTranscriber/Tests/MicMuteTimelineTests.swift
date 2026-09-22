@testable import MeetingTranscriber
import XCTest

final class MicMuteTimelineTests: XCTestCase {
    func testZoomUsesOwnMenuActionNotLaggingButtonOrOtherParticipants() {
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "us.zoom.xos", role: "AXMenuItem", identifier: "onMuteAudio:", value: "Mute audio"), .unmuted)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "us.zoom.xos", role: "AXMenuItem", identifier: "onMuteAudio:", value: "Unmute audio"), .muted)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "us.zoom.xos", role: "AXButton", identifier: "audio", value: "Mute audio"), .unknown)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "us.zoom.xos", role: "AXMenuItem", identifier: "onMuteAll:", value: "Mute audio"), .unknown)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "us.zoom.xos", role: "AXMenuItem", identifier: "onMuteAudio:", value: ""), .unknown)
    }

    func testTelemostCheckboxIsMutedWhenCheckedAndUnknownIsNotUnmuted() {
        let identifier = "TApplication.TelemostWindowTelemes.MainConferenceView.ControlPanelWidget.microphoneButton"
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "ru.yandex.desktop.telemost", role: "AXCheckBox", identifier: identifier, value: "1"), .muted)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "ru.yandex.desktop.telemost", role: "AXCheckBox", identifier: identifier, value: "0"), .unmuted)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "ru.yandex.desktop.telemost", role: "AXCheckBox", identifier: identifier, value: "2"), .unknown)
        XCTAssertEqual(MicMuteTimeline.state(bundleID: "other.app", role: "AXCheckBox", identifier: identifier, value: "0"), .unknown)
    }
}
