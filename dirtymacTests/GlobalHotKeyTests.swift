import XCTest
import Carbon.HIToolbox
@testable import dirtymac

final class GlobalHotKeyTests: XCTestCase {
    func testEveryPresetUsesThreeModifiersIncludingCommand() {
        for preset in HotKeyPreset.allCases where preset != .off {
            let mods = preset.binding!.modifiers
            XCTAssertNotEqual(mods & UInt32(cmdKey), 0, "\(preset)")
            let count = [controlKey, optionKey, shiftKey, cmdKey].filter { mods & UInt32($0) != 0 }.count
            XCTAssertEqual(count, 3, "\(preset)")
            XCTAssertFalse(preset.symbols.isEmpty)
        }
        XCTAssertNil(HotKeyPreset.off.binding)
    }

    func testPresetsAreDistinct() {
        let bindings = HotKeyPreset.allCases.compactMap(\.binding).map { "\($0.keyCode)-\($0.modifiers)" }
        XCTAssertEqual(Set(bindings).count, bindings.count)
    }

    func testRegisteringOffSucceedsWithoutAHotKey() {
        XCTAssertTrue(GlobalHotKey(action: {}).register(.off))
    }

    func testRegistersAndReleasesTheCombination() {
        let first = GlobalHotKey(action: {})
        XCTAssertTrue(first.register(.optShiftCmdK))

        // The same combination can't be taken twice.
        let second = GlobalHotKey(action: {})
        XCTAssertFalse(second.register(.optShiftCmdK))

        // Once released it is free again, and switching presets frees
        // the previous one.
        first.unregister()
        XCTAssertTrue(second.register(.optShiftCmdK))
        XCTAssertTrue(second.register(.ctrlOptCmdD))
        XCTAssertTrue(first.register(.optShiftCmdK))
        first.unregister()
        second.unregister()
    }

    func testStoredPresetFallsBackToTheDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: HotKeyPreset.defaultsKey)
        defer { defaults.set(saved, forKey: HotKeyPreset.defaultsKey) }

        defaults.removeObject(forKey: HotKeyPreset.defaultsKey)
        XCTAssertEqual(HotKeyPreset.current, HotKeyPreset.defaultValue)
        defaults.set("garbage", forKey: HotKeyPreset.defaultsKey)
        XCTAssertEqual(HotKeyPreset.current, HotKeyPreset.defaultValue)
        defaults.set(HotKeyPreset.off.rawValue, forKey: HotKeyPreset.defaultsKey)
        XCTAssertEqual(HotKeyPreset.current, .off)
    }
}
