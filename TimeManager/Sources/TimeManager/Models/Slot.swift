import Foundation

struct Slot: Identifiable, Hashable, Codable {
    let id: UUID
    var startAt: Date
    var endAt: Date
    var text: String
    var tagId: String?
    var originalBoundaries: [Date]
    var note: String

    init(
        id: UUID = UUID(),
        startAt: Date,
        endAt: Date,
        text: String = "",
        tagId: String? = nil,
        originalBoundaries: [Date] = [],
        note: String = ""
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.text = text
        self.tagId = tagId
        self.originalBoundaries = originalBoundaries
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, startAt, endAt, text, tagId, originalBoundaries, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startAt = try c.decode(Date.self, forKey: .startAt)
        endAt = try c.decode(Date.self, forKey: .endAt)
        text = try c.decode(String.self, forKey: .text)
        tagId = try c.decodeIfPresent(String.self, forKey: .tagId)
        originalBoundaries = (try? c.decode([Date].self, forKey: .originalBoundaries)) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    var durationMinutes: Int {
        Int(endAt.timeIntervalSince(startAt) / 60.0)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
