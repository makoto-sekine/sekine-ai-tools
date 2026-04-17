import SwiftUI

struct TimeLabelColumn: View {
    let ruler: TimeRuler

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ruler.rows) { row in
                Text(row.minute.formatted)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.timeLabelColor)
                    .shadow(color: AppTheme.timeLabelShadow, radius: 1.5, x: 0, y: 0.5)
                    .frame(height: AppTheme.slotRowHeight, alignment: .topTrailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.top, 1)
            }
        }
        .frame(width: AppTheme.timeLabelWidth)
    }
}
