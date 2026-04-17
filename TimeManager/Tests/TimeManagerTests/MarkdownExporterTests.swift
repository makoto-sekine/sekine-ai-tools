import XCTest
@testable import TimeManager

final class MarkdownExporterTests: XCTestCase {
    func testEmptyDay() {
        let day = DayData(date: DayDate(year: 2026, month: 4, day: 17))
        let text = MarkdownExporter.render(day: day, tags: .defaultLibrary)
        XCTAssertTrue(text.contains("（記録なし）"))
    }

    func testRendersTaggedSlots() {
        let calendar = Calendar.current
        let date = DayDate(year: 2026, month: 4, day: 17)
        let start = date.date(at: MinuteOfDay(hour: 10, minute: 0))
        let end = calendar.date(byAdding: .minute, value: 30, to: start)!
        let slot = Slot(
            startAt: start,
            endAt: end,
            text: "A社レビュー",
            tagId: "dev"
        )
        let day = DayData(date: date, slots: [slot])
        let text = MarkdownExporter.render(day: day, tags: .defaultLibrary)
        XCTAssertTrue(text.contains("10:00"))
        XCTAssertTrue(text.contains("[開発]"))
        XCTAssertTrue(text.contains("A社レビュー"))
    }
}
