import SwiftUI

struct DayHeaderView: View {
    let displayDay: DayDate
    let isToday: Bool
    let arrowShortcutEnabled: Bool
    let onPrev: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onPickDate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            prevButton
                .buttonStyle(.plain)
                .foregroundColor(Color.white.opacity(0.7))

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

            nextButton
                .buttonStyle(.plain)
                .foregroundColor(Color.white.opacity(0.7))

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

    @ViewBuilder
    private var prevButton: some View {
        if arrowShortcutEnabled {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
        } else {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if arrowShortcutEnabled {
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        } else {
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
        }
    }
}
