import Foundation

struct TimeRulerRow: Identifiable, Hashable {
    let minute: MinuteOfDay
    var id: Int { minute.value }
}

struct TimeRuler {
    let rows: [TimeRulerRow]

    init(range: (min: MinuteOfDay, max: MinuteOfDay)) {
        var result: [TimeRulerRow] = []
        var cursor = range.min.value
        let step = MinuteOfDay.slotLengthMinutes
        while cursor < range.max.value {
            result.append(TimeRulerRow(minute: MinuteOfDay(cursor)))
            cursor += step
        }
        self.rows = result
    }
}
