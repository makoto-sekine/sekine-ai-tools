import SwiftUI
import AppKit

struct ResizeHandle: View {
    let onResize: (Int) -> Void

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
                DragGesture(minimumDistance: 2, coordinateSpace: .local)
                    .onEnded { value in
                        let rows = Int((value.translation.height / AppTheme.slotRowHeight).rounded())
                        let minutesDelta = rows * MinuteOfDay.slotLengthMinutes
                        guard minutesDelta != 0 else { return }
                        onResize(minutesDelta)
                    }
            )
    }
}
