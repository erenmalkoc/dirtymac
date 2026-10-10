import XCTest
import AppKit
@testable import dirtymac

/// Pins what the tap intercepts and what it does with each event, so a
/// refactor can't quietly drop a key class, swallow the power button or
/// break the hold-Esc exit.
final class LockCoreTests: XCTestCase {
    private let systemDefinedBit = CGEventMask(1) << kCGEventSystemDefined

    private func mask(_ config: LockConfiguration) -> CGEventMask {
        EventMask.build(for: config.effective)
    }

    private func decide(_ type: CGEventType, keyCode: Int64 = 0, subtype: Int16? = nil) -> TapEventDecision {
        TapEventDecision.decide(type: type, keyCode: keyCode, systemSubtype: subtype)
    }

    // MARK: Event mask

    func testKeyDownAndKeyUpAreAlwaysIntercepted() {
        let configs = [
            LockConfiguration(),
            LockConfiguration(mode: .advanced, blockModifierKeys: false, blockMediaKeys: false),
        ]
        for config in configs {
            XCTAssertNotEqual(mask(config) & EventMask.bit(.keyDown), 0)
            XCTAssertNotEqual(mask(config) & EventMask.bit(.keyUp), 0)
        }
    }

    func testBasicModeBlocksKeysModifiersAndMediaButNeverThePointer() {
        // Whatever Advanced settings are stored, Basic is a fixed preset.
        let stored = LockConfiguration(
            mode: .basic,
            blockModifierKeys: false,
            blockMediaKeys: false,
            blockMouseAndTrackpad: true,
            autoUnlockSeconds: 60
        )
        let expected = EventMask.bit(.keyDown) | EventMask.bit(.keyUp)
            | EventMask.bit(.flagsChanged) | systemDefinedBit
        XCTAssertEqual(mask(stored), expected)
    }

    func testAdvancedTogglesMapOneToOne() {
        let keysOnly = mask(LockConfiguration(mode: .advanced, blockModifierKeys: false, blockMediaKeys: false))
        XCTAssertEqual(keysOnly, EventMask.bit(.keyDown) | EventMask.bit(.keyUp))

        let modifiers = mask(LockConfiguration(mode: .advanced, blockModifierKeys: true, blockMediaKeys: false))
        XCTAssertEqual(modifiers, keysOnly | EventMask.bit(.flagsChanged))

        let media = mask(LockConfiguration(mode: .advanced, blockModifierKeys: false, blockMediaKeys: true))
        XCTAssertEqual(media, keysOnly | systemDefinedBit)
    }

    func testMouseLockdownInterceptsEveryPointerEventAndGesture() {
        let config = LockConfiguration(mode: .advanced, blockMouseAndTrackpad: true)
        XCTAssertEqual(EventMask.pointerTypes.count, 11)
        for type in EventMask.pointerTypes {
            XCTAssertNotEqual(mask(config) & EventMask.bit(type), 0, "event type \(type.rawValue)")
        }
        XCTAssertEqual(EventMask.gestureBit, CGEventMask(1) << 29)
        XCTAssertNotEqual(mask(config) & EventMask.gestureBit, 0)
    }

    func testGesturesStayLiveWhileThePointerIsFree() {
        XCTAssertEqual(mask(LockConfiguration()) & EventMask.gestureBit, 0)
        XCTAssertEqual(mask(LockConfiguration(mode: .advanced)) & EventMask.gestureBit, 0)
    }

    func testGesturesAreBlockedByTheTapLikeOtherPointerEvents() throws {
        let gesture = try XCTUnwrap(CGEventType(rawValue: 29))
        XCTAssertEqual(decide(gesture), .block)
    }

    // MARK: Decisions

    func testEscapeDrivesTheHoldGesture() {
        XCTAssertEqual(decide(.keyDown, keyCode: kEscapeKeyCode), .escDown)
        XCTAssertEqual(decide(.keyUp, keyCode: kEscapeKeyCode), .escUp)
    }

    func testOtherKeysModifiersAndPointerEventsAreBlocked() {
        XCTAssertEqual(decide(.keyDown, keyCode: 0), .block)     // A
        XCTAssertEqual(decide(.keyUp, keyCode: 36), .block)      // Return
        XCTAssertEqual(decide(.flagsChanged, keyCode: kEscapeKeyCode), .block)
        for type in EventMask.pointerTypes {
            XCTAssertEqual(decide(type), .block, "event type \(type.rawValue)")
        }
    }

    func testOnlyAuxControlSystemEventsAreBlocked() throws {
        let systemDefined = try XCTUnwrap(CGEventType(rawValue: kCGEventSystemDefined))
        XCTAssertEqual(decide(systemDefined, subtype: kAuxControlButtonsSubtype), .block)
        // The power button (subtype 1) must stay a hardware way out.
        XCTAssertEqual(decide(systemDefined, subtype: 1), .pass)
        XCTAssertEqual(decide(systemDefined, subtype: 0), .pass)
        XCTAssertEqual(decide(systemDefined, subtype: nil), .pass)
    }

    func testADisabledTapIsTurnedBackOn() {
        XCTAssertEqual(decide(.tapDisabledByTimeout), .reEnable)
        XCTAssertEqual(decide(.tapDisabledByUserInput), .reEnable)
    }

    // MARK: Reading real events (creating events needs no permission)

    func testReadsTheKeyCodeOfARealKeyEvent() throws {
        let esc = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kEscapeKeyCode), keyDown: true))
        XCTAssertEqual(TapEventDecision.decide(type: .keyDown, event: esc), .escDown)
        XCTAssertEqual(TapEventDecision.decide(type: .keyUp, event: esc), .escUp)

        let a = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        XCTAssertEqual(TapEventDecision.decide(type: .keyDown, event: a), .block)
    }

    func testReadsTheSubtypeOfARealSystemDefinedEvent() throws {
        func systemEvent(subtype: Int16) throws -> CGEvent {
            let event = try XCTUnwrap(NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: subtype,
                data1: 0,
                data2: 0
            ))
            return try XCTUnwrap(event.cgEvent)
        }

        let media = try systemEvent(subtype: kAuxControlButtonsSubtype)
        XCTAssertEqual(media.type.rawValue, kCGEventSystemDefined)
        XCTAssertEqual(TapEventDecision.decide(type: media.type, event: media), .block)

        let power = try systemEvent(subtype: 1)
        XCTAssertEqual(TapEventDecision.decide(type: power.type, event: power), .pass)
    }
}
