import XCTest
@testable import GlanceCore

final class KeyComboTests: XCTestCase {
    func testDisplayStringOrdersModifiers() {
        let combo = KeyCombo(keyCode: 8, carbonModifiers: KeyCombo.cmdKey | KeyCombo.optionKey | KeyCombo.controlKey | KeyCombo.shiftKey)
        XCTAssertEqual(combo.displayString { _ in "c" }, "⌃⌥⇧⌘C")
        XCTAssertEqual(KeyCombo(keyCode: 0x31, carbonModifiers: KeyCombo.cmdKey).displayString { _ in nil }, "⌘Space")
        XCTAssertEqual(KeyCombo(keyCode: 0x7A, carbonModifiers: 0).displayString { _ in nil }, "F1")
    }

    func testValidity() {
        XCTAssertFalse(KeyCombo(keyCode: 8, carbonModifiers: 0).isValidGlobalHotKey)
        XCTAssertFalse(KeyCombo(keyCode: 8, carbonModifiers: KeyCombo.shiftKey).isValidGlobalHotKey)
        XCTAssertTrue(KeyCombo(keyCode: 8, carbonModifiers: KeyCombo.optionKey).isValidGlobalHotKey)
        XCTAssertTrue(KeyCombo(keyCode: 0x60, carbonModifiers: 0).isValidGlobalHotKey)
    }

    func testCodableRoundTripAndMasksUnknownBits() throws {
        let combo = KeyCombo(keyCode: 8, carbonModifiers: KeyCombo.cmdKey | (1 << 20))
        XCTAssertEqual(combo.carbonModifiers, KeyCombo.cmdKey)
        let data = try JSONEncoder().encode(combo)
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: data), combo)
    }
}

final class PaletteTests: XCTestCase {
    func testForkValuesForLatteAndMocha() {
        // From itsycal-catppuccin Themer.m.
        XCTAssertEqual(CatppuccinFlavor.latte.roles.background, 0xEFF1F5)
        XCTAssertEqual(CatppuccinFlavor.latte.roles.today, 0x8839EF)
        XCTAssertEqual(CatppuccinFlavor.latte.roles.selection, 0x7287FD)
        XCTAssertEqual(CatppuccinFlavor.mocha.roles.background, 0x1E1E2E)
        XCTAssertEqual(CatppuccinFlavor.mocha.roles.highlightedWeekdayBackground, 0x181825)
        XCTAssertEqual(CatppuccinFlavor.mocha.roles.weekNumberText, 0x7F849C)
        XCTAssertEqual(CatppuccinFlavor.mocha.roles.otherMonthText, 0x6C7086)
    }

    func testFrappeAndMacchiatoBases() {
        XCTAssertEqual(CatppuccinFlavor.frappe.roles.background, 0x303446)
        XCTAssertEqual(CatppuccinFlavor.macchiato.roles.background, 0x24273A)
        XCTAssertEqual(CatppuccinFlavor.frappe.roles.today, 0xCA9EE6)
        XCTAssertEqual(CatppuccinFlavor.macchiato.roles.today, 0xC6A0F6)
    }

    func testThemeChoiceAppearance() {
        XCTAssertNil(ThemeChoice.system.flavor(isDarkMode: true))
        XCTAssertEqual(ThemeChoice.catppuccinAuto.flavor(isDarkMode: true), .mocha)
        XCTAssertEqual(ThemeChoice.catppuccinAuto.flavor(isDarkMode: false), .latte)
        XCTAssertEqual(ThemeChoice.latte.forcedDark, false)
        XCTAssertEqual(ThemeChoice.macchiato.forcedDark, true)
        XCTAssertNil(ThemeChoice.system.forcedDark)
        XCTAssertEqual(ThemeChoice.frappe.displayName, "Catppuccin Frappé")
    }

    func testRGBAHex() {
        let c = RGBA(hex: 0xFF8000)
        XCTAssertEqual(c.r, 1)
        XCTAssertEqual(c.g, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(c.b, 0)
    }
}
