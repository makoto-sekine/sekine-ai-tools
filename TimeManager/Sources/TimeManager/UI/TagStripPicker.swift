import SwiftUI

struct TagStripPicker: View {
    let library: TagLibrary
    @Binding var selected: String?

    var body: some View {
        HStack(spacing: 4) {
            tagButton(id: nil, label: "–", color: .white.opacity(0.35))
            ForEach(library.tags.sorted(by: { $0.order < $1.order })) { tag in
                tagButton(id: tag.id, label: tag.name, color: Color(hex: tag.colorHex))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tagButton(id: String?, label: String, color: Color) -> some View {
        let isSelected = selected == id
        Button(action: { selected = id }) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? color : color.opacity(0.12))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}
