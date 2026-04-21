import SwiftUI

struct TimelineView: View {
    @ObservedObject var store: SlotStore
    @ObservedObject var clock: CurrentTimeObserver

    @State private var showDatePicker: Bool = false
    @State private var autoOpenSlotId: UUID?
    @State private var openEditorCount: Int = 0

    private let calendar = Calendar.current
    private let laneSpacing: CGFloat = 2

    var body: some View {
        let range = store.rangeMinutes()
        let ruler = TimeRuler(range: range)

        VStack(spacing: 0) {
            DayHeaderView(
                displayDay: store.currentDay,
                isToday: store.currentDay == .today(calendar: calendar),
                arrowShortcutEnabled: openEditorCount == 0 && !showDatePicker,
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

            ScrollView(.vertical, showsIndicators: true) {
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
        let laneMap = SlotLaneLayout.compute(slots: store.day.slots)

        GeometryReader { geo in
            let columnWidth = geo.size.width

            ZStack(alignment: .topLeading) {
                gridLines(ruler: ruler)

                ForEach(ruler.rows) { row in
                    if !isCoveredByPrecedingSlot(minute: row.minute),
                       slotStarting(at: row.minute) == nil {
                        EmptySlotView(minute: row.minute) { minute in
                            let created = store.ensureSlot(startingAt: minute)
                            autoOpenSlotId = created.id
                        }
                        .frame(width: columnWidth, height: AppTheme.slotRowHeight)
                        .offset(y: offsetY(for: row.minute, ruler: ruler))
                    }
                }

                ForEach(store.day.slots) { slot in
                    let duration = slotDurationMinutes(slot: slot)
                    let lane = laneMap[slot.id] ?? SlotLaneInfo(lane: 0, totalLanes: 1)
                    let (offsetX, width) = laneMetrics(laneInfo: lane, columnWidth: columnWidth)

                    FilledSlotView(
                        slot: slot,
                        tag: store.tags.tag(for: slot.tagId),
                        durationMinutes: duration,
                        autoOpenSlotId: $autoOpenSlotId,
                        openEditorCount: $openEditorCount,
                        onCommit: { id, text, tagId, note in
                            store.commit(slotId: id, text: text, tagId: tagId, note: note)
                            store.autoMergeSameTagNeighbors(of: id)
                        },
                        onRequestSplit: { id in store.split(slotId: id) },
                        onRequestMergeWithNext: { id in store.mergeWithNext(slotId: id) },
                        onRequestResize: { id, delta in store.resize(slotId: id, minutesDelta: delta) },
                        onRequestResizeStart: { id, delta in store.resizeStart(slotId: id, minutesDelta: delta) },
                        onRequestMove: { id, deltaMinutes in
                            let currentStart = MinuteOfDay.fromDate(slot.startAt, calendar: calendar)
                            let newStart = currentStart.adding(minutes: deltaMinutes)
                            store.move(slotId: id, toStartMinute: newStart)
                        },
                        onDelete: { id in store.delete(slotId: id) },
                        tagLibrary: store.tags
                    )
                    .frame(width: width, height: pixelHeight(forMinutes: duration), alignment: .topLeading)
                    .offset(x: offsetX, y: offsetY(forSlot: slot, ruler: ruler))
                }
            }
            .frame(width: columnWidth, height: totalHeight(ruler: ruler), alignment: .topLeading)
        }
        .frame(height: totalHeight(ruler: ruler))
    }

    private func laneMetrics(laneInfo: SlotLaneInfo, columnWidth: CGFloat) -> (offsetX: CGFloat, width: CGFloat) {
        let n = max(1, laneInfo.totalLanes)
        guard n > 1 else { return (0, columnWidth) }
        let totalSpacing = laneSpacing * CGFloat(n - 1)
        let laneWidth = (columnWidth - totalSpacing) / CGFloat(n)
        let offsetX = CGFloat(laneInfo.lane) * (laneWidth + laneSpacing)
        return (offsetX, laneWidth)
    }

    private func totalHeight(ruler: TimeRuler) -> CGFloat {
        CGFloat(ruler.rows.count) * AppTheme.slotRowHeight
    }

    private func offsetY(for minute: MinuteOfDay, ruler: TimeRuler) -> CGFloat {
        let minutesFromStart = minute.value - ruler.rows.first!.minute.value
        return pixelHeight(forMinutes: minutesFromStart)
    }

    private func pixelHeight(forMinutes minutes: Int) -> CGFloat {
        CGFloat(minutes) / CGFloat(MinuteOfDay.slotLengthMinutes) * AppTheme.slotRowHeight
    }

    private func offsetY(forSlot slot: Slot, ruler: TimeRuler) -> CGFloat {
        let startMinute = MinuteOfDay.fromDate(slot.startAt, calendar: calendar)
        return offsetY(for: startMinute, ruler: ruler)
    }

    @ViewBuilder
    private func gridLines(ruler: TimeRuler) -> some View {
        VStack(spacing: 0) {
            ForEach(ruler.rows) { row in
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(gridLineColor(for: row.minute))
                        .frame(height: row.minute.minute == 0 ? 0.8 : 0.4)
                    Spacer(minLength: 0)
                }
                .frame(height: AppTheme.slotRowHeight)
            }
            Rectangle()
                .fill(gridLineColor(for: ruler.endMinute))
                .frame(height: ruler.endMinute.minute == 0 ? 0.8 : 0.4)
        }
        .allowsHitTesting(false)
    }

    private func gridLineColor(for minute: MinuteOfDay) -> Color {
        minute.minute == 0
            ? Color.white.opacity(0.22)
            : Color.white.opacity(0.08)
    }

    private func slotStarting(at minute: MinuteOfDay) -> Slot? {
        let target = store.currentDay.date(at: minute, calendar: calendar)
        return store.day.slots.first { $0.startAt == target }
    }

    private func slotDurationMinutes(slot: Slot) -> Int {
        let startMinute = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).value
        let endMinute: Int
        let endDay = DayDate(date: slot.endAt, calendar: calendar)
        if endDay == store.currentDay {
            endMinute = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
        } else {
            endMinute = MinuteOfDay.dayEnd.value
        }
        return max(MinuteOfDay.snapGranularityMinutes, endMinute - startMinute)
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
