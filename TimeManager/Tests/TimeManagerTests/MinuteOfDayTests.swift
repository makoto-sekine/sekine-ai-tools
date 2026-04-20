import XCTest
@testable import TimeManager

final class MinuteOfDayTests: XCTestCase {
    func testClampingOutOfRange() {
        XCTAssertEqual(MinuteOfDay(-5).value, 0)
        XCTAssertEqual(MinuteOfDay(10_000).value, 24 * 60)
    }

    func testSnappingDownToThirty() {
        XCTAssertEqual(MinuteOfDay(619).snappedDown().value, 600)
        XCTAssertEqual(MinuteOfDay(630).snappedDown().value, 630)
        XCTAssertEqual(MinuteOfDay(629).snappedDown().value, 600)
    }

    func testFormatted() {
        XCTAssertEqual(MinuteOfDay(hour: 9, minute: 5).formatted, "09:05")
        XCTAssertEqual(MinuteOfDay(hour: 23, minute: 30).formatted, "23:30")
    }

    func testDayDateCodableRoundTrip() throws {
        let day = DayDate(year: 2026, month: 4, day: 17)
        let data = try JSONEncoder().encode(day)
        let decoded = try JSONDecoder().decode(DayDate.self, from: data)
        XCTAssertEqual(decoded, day)
    }
}
