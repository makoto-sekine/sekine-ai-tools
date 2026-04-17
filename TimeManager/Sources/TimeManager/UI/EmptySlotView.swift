import SwiftUI

struct EmptySlotView: View {
    let minute: MinuteOfDay
    let onClick: (MinuteOfDay) -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppTheme.capsuleCornerRadius, style: .continuous)
                .stroke(
                    hovering ? AppTheme.emptyHoverOutline : Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: hovering ? 1 : 0.5, dash: [3, 4])
                )
                .padding(.vertical, 3)

            if hovering {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("記入")
                }
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.75))
                .shadow(color: AppTheme.timeLabelShadow, radius: 1)
                .padding(.leading, 10)
            }
        }
        .frame(height: AppTheme.slotRowHeight, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onClick(minute) }
    }
}
