import XCTest
@testable import PlayerCore

final class ThemeColorTests: XCTestCase {
    func testHexRoundTripsAndRejectsPartialInput() {
        for hex in ["#000000", "#FFFFFF", "#C3DCA3", "#201C2B", "#F4F1EA"] {
            XCTAssertEqual(ThemeColor(hex: hex)?.hex, hex)
        }
        XCTAssertEqual(ThemeColor(hex: "  c3dca3 ")?.hex, "#C3DCA3")
        for hex in ["", "#ABC", "#FFFFFG", "1234567", "-00001", "AA#BBCC"] { XCTAssertNil(ThemeColor(hex: hex)) }
    }
    func testContrastUsesLinearSRGB() {
        XCTAssertEqual(ThemeColor.white.contrast(with: .black), 21, accuracy: 0.001)
        XCTAssertEqual(ThemeColor.black.contrast(with: .black), 1)
        XCTAssertEqual(ThemeColor(hex: "#777777")!.contrast(with: .white), 4.478, accuracy: 0.001)
    }
    func testAutomaticInkAndAccentRemainReadableOnLightAndDarkSurfaces() {
        let pairs = [("181E1C", "202925"), ("201C2B", "2C253B"), ("141F2B", "1D2D3B"), ("291D1B", "362724"), ("19191C", "242428"), ("F4F1EA", "E8E4DA")]
        for pair in pairs {
            let backgrounds = [ThemeColor(hex: pair.0)!, ThemeColor(hex: pair.1)!]
            for color in [ThemeColor.black, .white, ThemeColor(0.5, 0.5, 0.5), ThemeColor(0.7, 0.1, 0.9)] {
                let adjusted = color.readable(on: backgrounds, minimum: 4.5)
                for background in backgrounds { XCTAssertGreaterThanOrEqual(adjusted.contrast(with: background), 4.5) }
                XCTAssertGreaterThanOrEqual(adjusted.readableInk.contrast(with: adjusted), 4.5)
            }
        }
    }
}
