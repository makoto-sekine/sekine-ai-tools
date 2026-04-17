import Foundation

struct Slot: Identifiable, Hashable, Codable {
    let id: UUID
    var startAt: Date
    var endAt: Date
    var text: String
    var tagId: String?
    var originalBoundaries: [Date]

    init(
        id: UUID = UUID(),
        startAt: Date,
        endAt: Date,
        text: String = "",
        tagId: String? = nil,
        originalBoundaries: [Date] = []
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.text = text
        self.tagId = tagId
        self.originalBoundaries = originalBoundaries
    }

    var durationMinutes: Int {
        Int(endAt.timeIntervalSince(startAt) / 60.0)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
