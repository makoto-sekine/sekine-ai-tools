import SwiftUI

struct DatePickerSheet: View {
    @Binding var isPresented: Bool
    let initialDate: DayDate
    let onPick: (DayDate) -> Void

    @State private var selection: Date

    init(isPresented: Binding<Bool>, initialDate: DayDate, onPick: @escaping (DayDate) -> Void) {
        self._isPresented = isPresented
        self.initialDate = initialDate
        self.onPick = onPick
        _selection = State(initialValue: initialDate.date())
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("日付を選択")
                .font(.system(size: 13, weight: .semibold))
            DatePicker(
                "",
                selection: $selection,
                in: ...Date().addingTimeInterval(60 * 60 * 24),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button("キャンセル") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("開く") {
                    onPick(DayDate(date: selection))
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
