import SwiftUI

struct CurrentTimeIndicator: View {
    let offset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(AppTheme.currentTimeLine)
                .frame(width: 8, height: 8)
                .shadow(color: AppTheme.currentTimeLine.opacity(0.6), radius: 3)
            Rectangle()
                .fill(AppTheme.currentTimeLine)
                .frame(height: 1.3)
                .shadow(color: AppTheme.currentTimeLine.opacity(0.6), radius: 2)
        }
        .allowsHitTesting(false)
        .offset(y: offset)
    }
}
