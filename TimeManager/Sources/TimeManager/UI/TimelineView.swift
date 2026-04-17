import SwiftUI

struct TimelineView: View {
    @ObservedObject var store: SlotStore
    @ObservedObject var clock: CurrentTimeObserver

    @State private var focusedSlotId: UUID?
    @State private var showDatePicker: Bool = false

    private let calendar = Calendar.current

    var body: some View {
        let range = store.rangeMinutes()
        let ruler = TimeRuler(range: range)

        VStack(spacing: 0) {
            DayHeaderView(
                displayDay: store.currentDay,
                isToday: store.currentDay == .today(calendar: calendar),
                onPrev: { store.goToPreviousDay() },
                onNext: { store.goToNextDay() },
                onToday: { store.goToToday() },
                onPickDate: { showDatePicker = true }
            )
            .background(
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .blur(radius: 6)
                    .padding(-4)
            )
            .padding(.top, 6)

            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: 4) {
                        TimeLabelColumn(ruler: ruler)
                        slotsColumn(ruler: ruler)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, AppTheme.timelineVerticalPadding)

                    if shouldShowCurrentTimeLine() {
                        CurrentTimeIndicator(offset: currentTimeOffset(range: range))
                            .padding(.leading, AppTheme.timeLabelWidth + 10)
                            .padding(.top, AppTheme.timelineVerticalPadding)
                    }
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(
                isPresented: $showDatePicker,
                initialDate: store.currentDay,
                onPick: { store.switchTo(day: $0) }
            )
        }
    }

    @ViewBuilder
    private func slotsColumn(ruler: TimeRuler) -> some View {
        VStack(spacing: 0) {
            ForEach(ruler.rows) { row in
                rowContent(for: row)
            }
        }
    }

    @ViewBuilder
    private func rowContent(for row: TimeRulerRow) -> some View {
        if let slotStarting = slotStarting(at: row.minute) {
            let span = slotRowSpan(slot: slotStarting)
            FilledSlotView(
                slot: slotStarting,
                tag: store.tags.tag(for: slotStarting.tagId),
                rowsSpanned: span,
                focusedSlotId: $focusedSlotId,
                onCommit: { id, text, tagId in
                    store.commit(slotId: id, text: text, tagId: tagId)
                    store.autoMergeSameTagNeighbors(of: id)
                },
                onRequestSplit: { id in store.split(slotId: id) },
                onRequestMergeWithNext: { id in store.mergeWithNext(slotId: id) },
                onRequestResize: { id, delta in store.resize(slotId: id, minutesDelta: delta) },
                onDelete: { id in store.delete(slotId: id) },
                tagLibrary: store.tags
            )
        } else if !isCoveredByPrecedingSlot(minute: row.minute) {
            EmptySlotView(minute: row.minute) { minute in
                let created = store.ensureSlot(startingAt: minute)
                focusedSlotId = created.id
            }
        } else {
            Color.clear.frame(height: AppTheme.slotRowHeight)
        }
    }

    private func slotStarting(at minute: MinuteOfDay) -> Slot? {
        let target = store.currentDay.date(at: minute, calendar: calendar)
        return store.day.slots.first { $0.startAt == target }
    }

    private func slotRowSpan(slot: Slot) -> Int {
        let startMinute = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).value
        let endMinute: Int
        let endDay = DayDate(date: slot.endAt, calendar: calendar)
        if endDay == store.currentDay {
            endMinute = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
        } else {
            endMinute = MinuteOfDay.dayEnd.value
        }
        let minutes = max(MinuteOfDay.slotLengthMinutes, endMinute - startMinute)
        return minutes / MinuteOfDay.slotLengthMinutes
    }

    private func isCoveredByPrecedingSlot(minute: MinuteOfDay) -> Bool {
        let target = store.currentDay.date(at: minute, calendar: calendar)
        return store.day.slots.contains { slot in
            slot.startAt < target && slot.endAt > target
        }
    }

    private func shouldShowCurrentTimeLine() -> Bool {
        store.currentDay == .today(calendar: calendar)
    }

    private func currentTimeOffset(range: (min: MinuteOfDay, max: MinuteOfDay)) -> CGFloat {
        let nowMinutes = MinuteOfDay.fromDate(clock.now, calendar: calendar).value
        let clampedMinutes = max(range.min.value, min(nowMinutes, range.max.value))
        let offsetMinutes = clampedMinutes - range.min.value
        return CGFloat(offsetMinutes) * AppTheme.slotRowHeight / CGFloat(MinuteOfDay.slotLengthMinutes)
    }
}
