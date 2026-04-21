import Foundation

struct SlotLaneInfo: Hashable {
    let lane: Int
    let totalLanes: Int
}

enum SlotLaneLayout {
    /// Assigns a (lane, totalLanes) to each slot so that overlapping slots
    /// render side by side. Non-overlapping slots always get lane 0 / total 1.
    /// Groups are connected components under overlap; every slot in a group
    /// shares the same totalLanes (the peak concurrency within the group).
    static func compute(slots: [Slot]) -> [UUID: SlotLaneInfo] {
        let sorted = slots.sorted { a, b in
            if a.startAt != b.startAt { return a.startAt < b.startAt }
            return a.endAt > b.endAt
        }

        struct Active { let slot: Slot; let lane: Int }
        var active: [Active] = []
        var pendingIds: [UUID] = []
        var lanes: [UUID: Int] = [:]
        var totals: [UUID: Int] = [:]
        var currentMax = 0

        func flush() {
            for id in pendingIds { totals[id] = max(1, currentMax) }
            pendingIds.removeAll()
            currentMax = 0
        }

        for slot in sorted {
            active.removeAll { $0.slot.endAt <= slot.startAt }
            if active.isEmpty && !pendingIds.isEmpty { flush() }

            let used = Set(active.map { $0.lane })
            var lane = 0
            while used.contains(lane) { lane += 1 }

            active.append(Active(slot: slot, lane: lane))
            lanes[slot.id] = lane
            pendingIds.append(slot.id)
            currentMax = max(currentMax, active.count)
        }
        flush()

        var result: [UUID: SlotLaneInfo] = [:]
        for (id, lane) in lanes {
            result[id] = SlotLaneInfo(lane: lane, totalLanes: totals[id] ?? 1)
        }
        return result
    }
}
