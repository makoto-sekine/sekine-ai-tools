import SwiftUI

struct FilledSlotView: View {
    let slot: Slot
    let tag: TimelineTag?
    let durationMinutes: Int
    @Binding var autoOpenSlotId: UUID?
    @Binding var openEditorCount: Int
    let onCommit: (UUID, String, String?, String) -> Void
    let onRequestSplit: (UUID) -> Void
    let onRequestMergeWithNext: (UUID) -> Void
    let onRequestResize: (UUID, Int) -> Void
    let onRequestResizeStart: (UUID, Int) -> Void
    let onRequestMove: (UUID, Int) -> Void
    let onDelete: (UUID) -> Void
    let tagLibrary: TagLibrary

    @State private var showEditor = false
    @State private var hovering = false
    @State private var bottomResizePreviewMinutes: Int = 0
    @State private var topResizePreviewMinutes: Int = 0
    @State private var movePreviewMinutes: Int = 0
    @State private var isDragging = false

    var body: some View {
        let accent = tag.map { Color(hex: $0.colorHex) } ?? Color.white.opacity(0.4)
        let pixelsPerMinute = AppTheme.slotRowHeight / CGFloat(MinuteOfDay.slotLengthMinutes)
        let effectiveMinutes = max(
            MinuteOfDay.snapGranularityMinutes,
            durationMinutes - topResizePreviewMinutes + bottomResizePreviewMinutes
        )
        let slotHeight = CGFloat(effectiveMinutes) * pixelsPerMinute
        let yOffset = CGFloat(movePreviewMinutes + topResizePreviewMinutes) * pixelsPerMinute

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                if let tag {
                    Text(tag.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(0.18))
                        .cornerRadius(4)
                }
                Text(previewTimeLabel)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.7))
                if !slot.note.isEmpty {
                    Image(systemName: "note.text")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.7))
                        .help("メモあり")
                }
                Spacer(minLength: 0)
            }
            .frame(height: 20)

            if !slot.text.isEmpty {
                Text(slot.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("クリックして入力")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(
            maxWidth: .infinity,
            minHeight: slotHeight,
            maxHeight: slotHeight,
            alignment: .topLeading
        )
        .background(NonMovableBackground())
        .background(
            RoundedRectangle(cornerRadius: AppTheme.capsuleCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isDragging ? 0.75 : AppTheme.capsuleFillOpacity)
                .padding(.vertical, 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.capsuleCornerRadius, style: .continuous)
                .stroke(
                    isDragging ? accent.opacity(0.9)
                        : (hovering ? accent.opacity(0.7) : Color.white.opacity(0.08)),
                    lineWidth: isDragging ? 1.2 : (hovering ? 1.0 : 0.5)
                )
                .padding(.vertical, 3)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: AppTheme.accentBarWidth)
                .padding(.vertical, 9)
                .padding(.leading, 4)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            ResizeHandle(
                onPreview: { delta in topResizePreviewMinutes = delta },
                onCommit: { delta in
                    topResizePreviewMinutes = 0
                    guard delta != 0 else { return }
                    onRequestResizeStart(slot.id, delta)
                }
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .overlay(alignment: .bottom) {
            ResizeHandle(
                onPreview: { delta in bottomResizePreviewMinutes = delta },
                onCommit: { delta in
                    bottomResizePreviewMinutes = 0
                    guard delta != 0 else { return }
                    onRequestResize(slot.id, delta)
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .shadow(color: isDragging ? AppTheme.focusedSlotGlow : (hovering ? AppTheme.focusedSlotGlow : .clear), radius: isDragging ? 6 : (hovering ? 4 : 0))
        .offset(y: yOffset)
        .zIndex(isDragging ? 10 : 0)
        .onHover { hovering = $0 }
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
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    isDragging = true
                    movePreviewMinutes = snappedMinutes(from: value.translation.height)
                }
                .onEnded { value in
                    let delta = snappedMinutes(from: value.translation.height)
                    movePreviewMinutes = 0
                    isDragging = false
                    guard delta != 0 else { return }
                    onRequestMove(slot.id, delta)
                }
        )
        .onTapGesture {
            guard !isDragging else { return }
            showEditor = true
        }
        .onAppear {
            if autoOpenSlotId == slot.id {
                showEditor = true
                autoOpenSlotId = nil
            }
        }
        .popover(isPresented: $showEditor, arrowEdge: .leading) {
            SlotEditorView(
                slot: slot,
                tagLibrary: tagLibrary,
                onCommit: { text, tagId, note in onCommit(slot.id, text, tagId, note) },
                onDelete: { onDelete(slot.id) }
            )
        }
        .onChange(of: showEditor) { isOpen in
            if isOpen {
                openEditorCount += 1
            } else {
                openEditorCount = max(0, openEditorCount - 1)
            }
        }
    }

    private func snappedMinutes(from height: CGFloat) -> Int {
        let pixelsPerMinute = AppTheme.slotRowHeight / CGFloat(MinuteOfDay.slotLengthMinutes)
        let rawMinutes = height / pixelsPerMinute
        let snap = CGFloat(MinuteOfDay.snapGranularityMinutes)
        let snapped = (rawMinutes / snap).rounded() * snap
        return Int(snapped)
    }

    private var previewTimeLabel: String {
        let calendar = Calendar.current
        let startRaw = MinuteOfDay.fromDate(slot.startAt, calendar: calendar).value
        let endRaw = MinuteOfDay.fromDate(slot.endAt, calendar: calendar).value
        let normalizedEnd = endRaw == 0 ? MinuteOfDay.dayEnd.value : endRaw
        let adjustedStart = startRaw + movePreviewMinutes + topResizePreviewMinutes
        let adjustedEnd = normalizedEnd + movePreviewMinutes + bottomResizePreviewMinutes
        let start = MinuteOfDay(max(0, adjustedStart))
        let end = MinuteOfDay(max(start.value + MinuteOfDay.slotLengthMinutes, adjustedEnd))
        return "\(start.formatted)–\(end.formatted)"
    }
}
