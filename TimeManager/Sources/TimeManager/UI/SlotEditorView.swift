import SwiftUI

struct SlotEditorView: View {
    let slot: Slot
    let tagLibrary: TagLibrary
    let onCommit: (String, String?, String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String
    @State private var draftTagId: String?
    @State private var draftNote: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case text
        case note
    }

    init(
        slot: Slot,
        tagLibrary: TagLibrary,
        onCommit: @escaping (String, String?, String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.slot = slot
        self.tagLibrary = tagLibrary
        self.onCommit = onCommit
        self.onDelete = onDelete
        _draftText = State(initialValue: slot.text)
        _draftTagId = State(initialValue: slot.tagId)
        _draftNote = State(initialValue: slot.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TextField("内容を入力", text: $draftText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focusedField, equals: .text)
                .onSubmit {
                    commit()
                    dismiss()
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("タグ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                TagStripPicker(library: tagLibrary, selected: $draftTagId)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("メモ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                TextEditor(text: $draftNote)
                    .font(.system(size: 12))
                    .focused($focusedField, equals: .note)
                    .frame(minHeight: 70, maxHeight: 140)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
            }

            HStack {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("削除", systemImage: "trash")
                }
                Spacer()
                Text(focusedField == .note ? "メモ欄では改行できます" : "Enter で保存")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { focusedField = .text }
        .onDisappear { commit() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(timeLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Spacer()
            if let tag = tagLibrary.tag(for: draftTagId) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 8, height: 8)
                    Text(tag.name)
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
        }
    }

    private var timeLabel: String {
        let calendar = Calendar.current
        let start = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).formatted
        let endMinute: Int = {
            let end = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
            return end == 0 ? MinuteOfDay.dayEnd.value : end
        }()
        let end = MinuteOfDay(endMinute).formatted
        return "\(start) – \(end)"
    }

    private func commit() {
        onCommit(draftText, draftTagId, draftNote)
    }
}
