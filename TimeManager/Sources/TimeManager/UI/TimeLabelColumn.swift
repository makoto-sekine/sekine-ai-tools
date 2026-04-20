import SwiftUI

struct TimeLabelColumn: View {
    let ruler: TimeRuler

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ruler.rows) { row in
                label(for: row.minute)
                    .frame(height: AppTheme.slotRowHeight, alignment: .topTrailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .offset(y: -4)
            }

            label(for: ruler.endMinute)
                .frame(height: 0, alignment: .topTrailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .offset(y: -4)
        }
        .frame(width: AppTheme.timeLabelWidth)
    }

    @ViewBuilder
    private func label(for minute: MinuteOfDay) -> some View {
        Text(minute.formatted)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(AppTheme.timeLabelColor)
            .shadow(color: AppTheme.timeLabelShadow, radius: 1.5, x: 0, y: 0.5)
    }
}
