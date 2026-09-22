import AppKit
import ApplicationServices
import AVFoundation
import Foundation

/// All mutable state and AX references belong to one serial queue. stop() drains
/// that queue; the audio callback never waits on UI automation. No AX writes.
final class MicMuteObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.meetingtranscriber.mute")
    private let pid: pid_t
    private let bundleID: String
    private var timer: (any DispatchSourceTimer)?
    private var samples: [MicMuteTimeline.Observation] = []

    init(pid: pid_t, bundleID: String) {
        self.pid = pid
        self.bundleID = bundleID
    }

    func start() {
        queue.sync {
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(20))
            source.setEventHandler { [weak self] in self?.poll() }
            timer = source
            source.resume()
        }
    }

    func stop(microphoneOrigin: Double?) -> MicMuteTimeline {
        queue.sync {
            timer?.cancel()
            timer = nil
            // Without the actual file anchor no observation may admit mic audio.
            guard let origin = microphoneOrigin, origin.isFinite else {
                return MicMuteTimeline(bundleID: bundleID)
            }
            return MicMuteTimeline(bundleID: bundleID, observations: samples.map { sample in
                .init(timeSeconds: sample.timeSeconds - origin, state: sample.state)
            })
        }
    }

    private static func now() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    private func poll() {
        let began = Self.now()
        let state = readState(deadline: began + 0.18)
        let ended = Self.now()
        // A slow AX reply must not retrospectively authorise an entire gap.
        samples.append(.init(timeSeconds: ended, state: ended - began <= 0.3 ? state : .unknown))
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func state(_ element: AXUIElement) -> MicMuteTimeline.State {
        guard let enabled = attribute(element, kAXEnabledAttribute) as? Bool, enabled else { return .unknown }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
        let value: String = if bundleID == "ru.yandex.desktop.telemost" {
            (attribute(element, kAXValueAttribute) as? Int).map(String.init) ?? ""
        } else {
            attribute(element, kAXTitleAttribute) as? String ?? ""
        }
        return MicMuteTimeline.state(bundleID: bundleID, role: role, identifier: identifier, value: value)
    }

    private struct ElementKey: Hashable {
        let element: AXUIElement
        static func == (lhs: Self, rhs: Self) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private func readState(deadline: Double) -> MicMuteTimeline.State {
        guard AXIsProcessTrusted(),
              ["us.zoom.xos", "ru.yandex.desktop.telemost"].contains(bundleID),
              NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID
        else { return .unknown }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.03)
        let scanRoot: AXUIElement
        if bundleID == "us.zoom.xos" {
            guard let menu = attribute(root, kAXMenuBarAttribute),
                  CFGetTypeID(menu) == AXUIElementGetTypeID() else { return .unknown }
            scanRoot = unsafeDowncast(menu, to: AXUIElement.self)
        } else {
            scanRoot = root
        }
        var stack: [(AXUIElement, Int)] = [(scanRoot, 0)]
        var visited = Set<ElementKey>()
        var candidate: AXUIElement?
        var result = MicMuteTimeline.State.unknown
        while let (element, depth) = stack.popLast() {
            guard Self.now() < deadline, visited.count < 3000 else { return .unknown }
            guard visited.insert(ElementKey(element: element)).inserted else { continue }
            let identifier = attribute(element, kAXIdentifierAttribute) as? String ?? ""
            if identifier == "onMuteAudio:" || identifier.hasSuffix("MainConferenceView.ControlPanelWidget.microphoneButton") {
                let found = state(element)
                guard found != .unknown else { return .unknown }
                if candidate != nil, result != found { return .unknown }
                candidate = element
                result = found
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty {
                guard depth < 24 else { return .unknown }
                stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return result
    }
}
