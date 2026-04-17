import Foundation

struct TimelineTag: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var colorHex: String
    var order: Int
}

struct TagLibrary: Codable {
    var tags: [TimelineTag]

    static let defaultLibrary = TagLibrary(tags: [
        TimelineTag(id: "dev", name: "開発", colorHex: "#4C9AFF", order: 0),
        TimelineTag(id: "mtg", name: "会議", colorHex: "#F7B955", order: 1),
        TimelineTag(id: "break", name: "休憩", colorHex: "#6BCB77", order: 2),
        TimelineTag(id: "research", name: "調査", colorHex: "#A66DD4", order: 3),
        TimelineTag(id: "other", name: "その他", colorHex: "#9AA0A6", order: 4)
    ])

    func tag(for id: String?) -> TimelineTag? {
        guard let id else { return nil }
        return tags.first { $0.id == id }
    }
}
