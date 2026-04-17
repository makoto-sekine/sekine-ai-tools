import SwiftUI

struct FilledSlotView: View {
    let slot: Slot
    let tag: TimelineTag?
    let rowsSpanned: Int
    @Binding var focusedSlotId: UUID?
    let onCommit: (UUID, String, String?) -> Void
    let onRequestSplit: (UUID) -> Void
    let onRequestMergeWithNext: (UUID) -> Void
    let onRequestResize: (UUID, Int) -> Void
    let onDelete: (UUID) -> Void
    let tagLibrary: TagLibrary

    @State private var draftText: String = ""
    @State private var draftTagId: String?
    @State private var isEditing: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let accent = tag.map { Color(hex: $0.colorHex) } ?? Color.white.opacity(0.4)
        let isFocused = focusedSlotId == slot.id

        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: AppTheme.accentBarWidth)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    editingBody(accent: accent)
                } else {
                    displayBody(accent: accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.capsuleCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(AppTheme.capsuleFillOpacity)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.capsuleCornerRadius, style: .continuous)
                .stroke(isFocused ? accent.opacity(0.8) : Color.white.opacity(0.08), lineWidth: isFocused ? 1.0 : 0.5)
        )
        .shadow(color: isFocused ? AppTheme.focusedSlotGlow : .clear, radius: isFocused ? 6 : 0)
        .frame(height: CGFloat(rowsSpanned) * AppTheme.slotRowHeight - 6, alignment: .top)
        .padding(.vertical, 3)
        .contextMenu {
            Button("+30分 延長") { onRequestResize(slot.id, MinuteOfDay.slotLengthMinutes) }
            Button("−30分 短縮") { onRequestResize(slot.id, -MinuteOfDay.slotLengthMinutes) }
                .disabled(slot.durationMinutes <= MinuteOfDay.slotLengthMinutes)
            Divider()
            Button("分割", action: { onRequestSplit(slot.id) })
                .disabled(slot.durationMinutes <= MinuteOfDay.slotLengthMinutes)
            Button("次のスロットと結合", action: { onRequestMergeWithNext(slot.id) })
            Divider()
            Button("削除", role: .destructive) { onDelete(slot.id) }
        }
        .onTapGesture {
            beginEditing()
        }
    }

    @ViewBuilder
    private func displayBody(accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let tag {
                Text(tag.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accent.opacity(0.18))
                    .cornerRadius(4)
            }
            Text(timeLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
            Spacer(minLength: 0)
        }

        Text(slot.text.isEmpty ? "（クリックして入力）" : slot.text)
            .font(.system(size: 13))
            .foregroundColor(slot.text.isEmpty ? Color.white.opacity(0.45) : Color.white)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func editingBody(accent: Color) -> some View {
        HStack(spacing: 6) {
            Text(timeLabel)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.7))
            Spacer(minLength: 0)
        }

        TextField("内容を入力", text: $draftText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .focused($fieldFocused)
            .onSubmit { commit() }
            .onExitCommand { cancel() }

        TagStripPicker(
            library: tagLibrary,
            selected: $draftTagId
        )
    }

    private var timeLabel: String {
        let calendar = Calendar.current
        let start = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).formatted
        let endMinute: Int = {
            let end = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
            return end == 0 ? MinuteOfDay.dayEnd.value : end
        }()
        let end = MinuteOfDay(endMinute).formatted
        return "\(start)–\(end)"
    }

    private func beginEditing() {
        draftText = slot.text
        draftTagId = slot.tagId
        isEditing = true
        focusedSlotId = slot.id
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commit() {
        onCommit(slot.id, draftText, draftTagId)
        isEditing = false
        focusedSlotId = nil
    }

    private func cancel() {
        isEditing = false
        focusedSlotId = nil
    }
}
