import SwiftUI
import AppKit

struct NonMovableBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NonMovableView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class NonMovableView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
