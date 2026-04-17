import SwiftUI

struct DayHeaderView: View {
    let displayDay: DayDate
    let isToday: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onPickDate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.white.opacity(0.7))
            .keyboardShortcut(.leftArrow, modifiers: [])

            Spacer(minLength: 0)

            Button(action: onPickDate) {
                HStack(spacing: 6) {
                    Text(displayDay.key)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    if !isToday {
                        Text("過去")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(3)
                    }
                }
                .foregroundColor(.white)
                .shadow(color: AppTheme.timeLabelShadow, radius: 1.5)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundColor(Color.white.opacity(0.7))
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button(action: onToday) {
                Image(systemName: "dot.circle")
            }
            .buttonStyle(.plain)
            .foregroundColor(isToday ? Color.white.opacity(0.3) : Color.white.opacity(0.85))
            .disabled(isToday)
            .help("今日に戻る")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
