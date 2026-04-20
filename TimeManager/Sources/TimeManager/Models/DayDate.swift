import Foundation

struct DayDate: Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func today(calendar: Calendar = .current) -> DayDate {
        DayDate(date: Date(), calendar: calendar)
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 2000
        self.month = components.month ?? 1
        self.day = components.day ?? 1
    }

    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var description: String { key }

    func date(at minute: MinuteOfDay = .dayStart, calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = minute.hour
        components.minute = minute.minute
        return calendar.date(from: components) ?? Date()
    }

    func adding(days: Int, calendar: Calendar = .current) -> DayDate {
        let base = date(calendar: calendar)
        let shifted = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return DayDate(date: shifted, calendar: calendar)
    }

    static func < (lhs: DayDate, rhs: DayDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

extension DayDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid DayDate format: \(raw)"
            )
        }
        self.init(year: y, month: m, day: d)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}
