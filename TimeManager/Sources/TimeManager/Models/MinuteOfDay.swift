import Foundation

struct MinuteOfDay: Hashable, Comparable, CustomStringConvertible {
    let value: Int

    init(_ value: Int) {
        self.value = max(0, min(value, 24 * 60))
    }

    init(hour: Int, minute: Int) {
        self.init(hour * 60 + minute)
    }

    static func fromDate(_ date: Date, calendar: Calendar = .current) -> MinuteOfDay {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return MinuteOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    var hour: Int { value / 60 }
    var minute: Int { value % 60 }

    func snappedDown(toSlotMinutes minutes: Int = 30) -> MinuteOfDay {
        MinuteOfDay((value / minutes) * minutes)
    }

    func adding(minutes: Int) -> MinuteOfDay {
        MinuteOfDay(value + minutes)
    }

    var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var description: String { formatted }

    static func < (lhs: MinuteOfDay, rhs: MinuteOfDay) -> Bool {
        lhs.value < rhs.value
    }
}

extension MinuteOfDay {
    static let dayStart = MinuteOfDay(0)
    static let dayEnd = MinuteOfDay(24 * 60)
    static let defaultStart = MinuteOfDay(hour: 10, minute: 0)
    static let defaultEnd = MinuteOfDay(hour: 19, minute: 0)
    static let slotLengthMinutes = 30
    /// Snap granularity for move/resize interactions. The display grid still uses
    /// `slotLengthMinutes`, but users can position/resize slots at this finer grain.
    static let snapGranularityMinutes = 15
}
