import Foundation
import Combine

@MainActor
final class SlotStore: ObservableObject {
    @Published private(set) var currentDay: DayDate
    @Published private(set) var day: DayData
    @Published private(set) var tags: TagLibrary
    @Published private(set) var settings: AppSettings

    private let dayStore: DayFileStore
    private let tagStore: TagStore
    private let settingsStore: SettingsStore
    private let calendar: Calendar

    init(
        initialDate: DayDate = .today(),
        dayStore: DayFileStore = .init(),
        tagStore: TagStore = .init(),
        settingsStore: SettingsStore = .init(),
        calendar: Calendar = .current
    ) {
        self.dayStore = dayStore
        self.tagStore = tagStore
        self.settingsStore = settingsStore
        self.calendar = calendar
        self.currentDay = initialDate
        self.tags = tagStore.load()
        self.settings = settingsStore.load()
        self.day = dayStore.load(initialDate)
        ensureFolderStructure()
        ensureSlotGrid()
    }

    private func ensureFolderStructure() {
        try? FileStoreLocation.ensureDirectoryStructure()
        tagStore.ensureSeeded()
    }

    // MARK: - Day switching

    func switchTo(day: DayDate) {
        guard day != currentDay else { return }
        currentDay = day
        let loaded = dayStore.load(day)
        var working = loaded
        if working.slots.isEmpty {
            working.minSlotMinute = settings.defaultStartMinute
            working.maxSlotMinute = settings.defaultEndMinute
        }
        self.day = working
        ensureSlotGrid()
    }

    func goToPreviousDay() {
        switchTo(day: currentDay.adding(days: -1))
    }

    func goToNextDay() {
        switchTo(day: currentDay.adding(days: 1))
    }

    func goToToday() {
        switchTo(day: .today(calendar: calendar))
    }

    // MARK: - Range management

    func rangeMinutes() -> (min: MinuteOfDay, max: MinuteOfDay) {
        (MinuteOfDay(day.minSlotMinute), MinuteOfDay(day.maxSlotMinute))
    }

    private func ensureSlotGrid() {
        let (rangeMin, rangeMax) = extendedRangeFromSlots()
        day.minSlotMinute = rangeMin.value
        day.maxSlotMinute = rangeMax.value
    }

    private func extendedRangeFromSlots() -> (MinuteOfDay, MinuteOfDay) {
        var minMinute = day.minSlotMinute
        var maxMinute = day.maxSlotMinute
        for slot in day.slots {
            let slotStart = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).value
            let slotEnd = slotEndMinute(for: slot)
            if slotStart < minMinute { minMinute = (slotStart / MinuteOfDay.slotLengthMinutes) * MinuteOfDay.slotLengthMinutes }
            if slotEnd > maxMinute { maxMinute = ((slotEnd + MinuteOfDay.slotLengthMinutes - 1) / MinuteOfDay.slotLengthMinutes) * MinuteOfDay.slotLengthMinutes }
        }
        minMinute = max(0, min(minMinute, MinuteOfDay.defaultStart.value))
        maxMinute = min(MinuteOfDay.dayEnd.value, max(maxMinute, MinuteOfDay.defaultEnd.value))
        return (MinuteOfDay(minMinute), MinuteOfDay(maxMinute))
    }

    private func slotEndMinute(for slot: Slot) -> Int {
        let endDay = DayDate(date: slot.endAt, calendar: calendar)
        if endDay == currentDay {
            return MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
        }
        // Crosses midnight — cap at day end in today's terms
        return MinuteOfDay.dayEnd.value
    }

    func expandRangeIfNeeded(toContain minute: MinuteOfDay) {
        if minute.value < day.minSlotMinute {
            day.minSlotMinute = max(0, (minute.value / MinuteOfDay.slotLengthMinutes) * MinuteOfDay.slotLengthMinutes)
            persist()
        } else if minute.value >= day.maxSlotMinute {
            let ceilMinute = ((minute.value + MinuteOfDay.slotLengthMinutes) / MinuteOfDay.slotLengthMinutes) * MinuteOfDay.slotLengthMinutes
            day.maxSlotMinute = min(MinuteOfDay.dayEnd.value, ceilMinute)
            persist()
        }
    }

    func restoreDefaultRangeIfEmpty() {
        guard day.date == .today(calendar: calendar), day.slots.isEmpty else { return }
        day.minSlotMinute = settings.defaultStartMinute
        day.maxSlotMinute = settings.defaultEndMinute
        persist()
    }

    // MARK: - Slot lookup

    func slot(coveringSlotStart minute: MinuteOfDay) -> Slot? {
        let slotStartDate = currentDay.date(at: minute, calendar: calendar)
        let slotEndDate = currentDay.date(at: minute.adding(minutes: MinuteOfDay.slotLengthMinutes), calendar: calendar)
        return day.slots.first { slot in
            slot.startAt <= slotStartDate && slot.endAt >= slotEndDate
        }
    }

    func slot(startingAt minute: MinuteOfDay) -> Slot? {
        let target = currentDay.date(at: minute, calendar: calendar)
        return day.slots.first { $0.startAt == target }
    }

    // MARK: - Commit / delete

    func commit(slotId: UUID, text: String, tagId: String?) {
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }) else { return }
        let trimmed = text
        let shouldDelete = trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (tagId == nil)
        if shouldDelete {
            let removed = day.slots.remove(at: index)
            dayStore.moveToTrash(slot: removed, from: currentDay)
        } else {
            day.slots[index].text = trimmed
            day.slots[index].tagId = tagId
        }
        persist()
    }

    @discardableResult
    func ensureSlot(startingAt minute: MinuteOfDay) -> Slot {
        if let existing = slot(startingAt: minute) { return existing }
        let startDate = currentDay.date(at: minute, calendar: calendar)
        let endDate = currentDay.date(at: minute.adding(minutes: MinuteOfDay.slotLengthMinutes), calendar: calendar)
        let slot = Slot(startAt: startDate, endAt: endDate)
        day.slots.append(slot)
        day.slots.sort { $0.startAt < $1.startAt }
        expandRangeIfNeeded(toContain: minute.adding(minutes: MinuteOfDay.slotLengthMinutes))
        persist()
        return slot
    }

    func delete(slotId: UUID) {
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }) else { return }
        let removed = day.slots.remove(at: index)
        dayStore.moveToTrash(slot: removed, from: currentDay)
        persist()
    }

    // MARK: - Merge / split

    func mergeWithNext(slotId: UUID) {
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }),
              index + 1 < day.slots.count else { return }
        let current = day.slots[index]
        let next = day.slots[index + 1]
        guard current.endAt == next.startAt else { return }
        var merged = current
        merged.endAt = next.endAt
        merged.originalBoundaries.append(current.endAt)
        merged.originalBoundaries.append(contentsOf: next.originalBoundaries)
        if merged.text.isEmpty { merged.text = next.text }
        if merged.tagId == nil { merged.tagId = next.tagId }
        day.slots[index] = merged
        day.slots.remove(at: index + 1)
        persist()
    }

    func split(slotId: UUID) {
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }) else { return }
        let slot = day.slots[index]
        guard slot.durationMinutes > MinuteOfDay.slotLengthMinutes else { return }

        let boundary: Date
        if let restore = slot.originalBoundaries.first, slot.startAt < restore, restore < slot.endAt {
            boundary = restore
        } else {
            let midMinutes = slot.durationMinutes / 2
            let snapped = (midMinutes / MinuteOfDay.slotLengthMinutes) * MinuteOfDay.slotLengthMinutes
            let adjusted = max(MinuteOfDay.slotLengthMinutes, snapped)
            boundary = calendar.date(byAdding: .minute, value: adjusted, to: slot.startAt) ?? slot.endAt
        }

        var firstHalf = slot
        firstHalf.endAt = boundary
        firstHalf.originalBoundaries = slot.originalBoundaries.filter { $0 < boundary }

        let secondHalf = Slot(
            startAt: boundary,
            endAt: slot.endAt,
            text: "",
            tagId: slot.tagId,
            originalBoundaries: slot.originalBoundaries.filter { $0 > boundary }
        )
        day.slots[index] = firstHalf
        day.slots.insert(secondHalf, at: index + 1)
        day.slots.sort { $0.startAt < $1.startAt }
        persist()
    }

    func resize(slotId: UUID, minutesDelta: Int) {
        guard minutesDelta % MinuteOfDay.slotLengthMinutes == 0, minutesDelta != 0 else { return }
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }) else { return }
        let slot = day.slots[index]
        let newEnd = calendar.date(byAdding: .minute, value: minutesDelta, to: slot.endAt) ?? slot.endAt
        let newMinutes = Int(newEnd.timeIntervalSince(slot.startAt) / 60.0)
        guard newMinutes >= MinuteOfDay.slotLengthMinutes else { return }

        if minutesDelta > 0 {
            // Must not overlap with next slot
            if index + 1 < day.slots.count, day.slots[index + 1].startAt < newEnd {
                return
            }
        }
        day.slots[index].endAt = newEnd
        expandRangeIfNeeded(toContain: MinuteOfDay.fromDate(newEnd, calendar: calendar))
        persist()
    }

    func autoMergeSameTagNeighbors(of slotId: UUID) {
        guard settings.autoMergeSameTag else { return }
        guard let index = day.slots.firstIndex(where: { $0.id == slotId }) else { return }
        let current = day.slots[index]
        guard let tagId = current.tagId else { return }

        // Merge with next if adjacent + same tag
        if index + 1 < day.slots.count {
            let next = day.slots[index + 1]
            if next.tagId == tagId, next.startAt == current.endAt {
                mergeWithNext(slotId: current.id)
                autoMergeSameTagNeighbors(of: current.id)
                return
            }
        }
        // Merge with previous if adjacent + same tag
        if index > 0 {
            let prev = day.slots[index - 1]
            if prev.tagId == tagId, prev.endAt == current.startAt {
                mergeWithNext(slotId: prev.id)
                autoMergeSameTagNeighbors(of: prev.id)
            }
        }
    }

    // MARK: - Tags / settings mutation

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        settings = copy
        settingsStore.save(copy)
    }

    // MARK: - Persistence

    private func persist() {
        day.slots.sort { $0.startAt < $1.startAt }
        ensureSlotGrid()
        dayStore.save(day)
    }

    // MARK: - Public reload (e.g. after external edit)

    func reloadCurrentDay() {
        day = dayStore.load(currentDay)
        ensureSlotGrid()
    }
}
