import Foundation

enum MarkdownExporter {
    static func render(day: DayData, tags: TagLibrary) -> String {
        var lines: [String] = []
        lines.append("# \(day.date.key) の記録")
        lines.append("")
        if day.slots.isEmpty {
            lines.append("（記録なし）")
            return lines.joined(separator: "\n")
        }

        let calendar = Calendar.current
        for slot in day.slots.sorted(by: { $0.startAt < $1.startAt }) {
            let startMinute = MinuteOfDay.fromDate(slot.startAt, calendar: calendar)
            let endDay = DayDate(date: slot.endAt, calendar: calendar)
            let endLabel: String
            if endDay == day.date {
                endLabel = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).formatted
            } else {
                endLabel = "24:00"
            }
            let tagName = tags.tag(for: slot.tagId)?.name
            let tagText = tagName.map { "[\($0)] " } ?? ""
            let body = slot.text.isEmpty ? "（未入力）" : slot.text
            lines.append("- \(startMinute.formatted)–\(endLabel) \(tagText)\(body)")
        }
        return lines.joined(separator: "\n")
    }
}
