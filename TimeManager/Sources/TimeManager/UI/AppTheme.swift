import SwiftUI

enum AppTheme {
    static let slotRowHeight: CGFloat = 58
    static let timeLabelWidth: CGFloat = 56
    static let capsuleCornerRadius: CGFloat = 10
    static let accentBarWidth: CGFloat = 3
    static let windowDefaultWidth: CGFloat = 280
    static let timelineVerticalPadding: CGFloat = 16

    static let timeLabelColor = Color.white.opacity(0.85)
    static let timeLabelShadow = Color.black.opacity(0.55)
    static let emptyHoverOutline = Color.white.opacity(0.35)
    static let capsuleFillOpacity: Double = 0.96
    static let currentTimeLine = Color(red: 0.92, green: 0.26, blue: 0.32)
    static let focusedSlotGlow = Color.white.opacity(0.18)
}

extension Color {
    init(hex: String) {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
