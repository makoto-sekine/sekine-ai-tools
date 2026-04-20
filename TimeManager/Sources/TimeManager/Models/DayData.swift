import Foundation

struct DayData: Codable {
    var date: DayDate
    var minSlotMinute: Int
    var maxSlotMinute: Int
    var slots: [Slot]

    init(
        date: DayDate,
        minSlotMinute: Int = MinuteOfDay.defaultStart.value,
        maxSlotMinute: Int = MinuteOfDay.defaultEnd.value,
        slots: [Slot] = []
    ) {
        self.date = date
        self.minSlotMinute = minSlotMinute
        self.maxSlotMinute = maxSlotMinute
        self.slots = slots
    }

    static func empty(for date: DayDate) -> DayData {
        DayData(date: date)
    }
}
