import SwiftUI
import AppKit

struct ResizeHandle: View {
    let onPreview: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var cursorPushed = false

    var body: some View {
        Color.white.opacity(0.001)
            .frame(height: 8)
            .background(NonMovableBackground())
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    if !cursorPushed {
                        NSCursor.resizeUpDown.push()
                        cursorPushed = true
                    }
                } else if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        onPreview(snappedMinutes(from: value.translation.height))
                    }
                    .onEnded { value in
                        let minutesDelta = snappedMinutes(from: value.translation.height)
                        onCommit(minutesDelta)
                    }
            )
    }

    private func snappedMinutes(from height: CGFloat) -> Int {
        let pixelsPerMinute = AppTheme.slotRowHeight / CGFloat(MinuteOfDay.slotLengthMinutes)
        let rawMinutes = height / pixelsPerMinute
        let snap = CGFloat(MinuteOfDay.snapGranularityMinutes)
        let snapped = (rawMinutes / snap).rounded() * snap
        return Int(snapped)
    }
}
