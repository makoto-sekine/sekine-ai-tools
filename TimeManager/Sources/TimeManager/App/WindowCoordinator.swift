import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let window: BorderlessKeyWindow
    private let store: SlotStore
    private let clock: CurrentTimeObserver

    private let frameDefaultsKey = "TimeManager.windowFrame"

    private var isForegroundTemporary = false

    init(store: SlotStore, clock: CurrentTimeObserver) {
        self.store = store
        self.clock = clock

        let initialFrame = Self.loadSavedFrame() ?? Self.defaultFrame()

        self.window = BorderlessKeyWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureWindow()
        installContentView()
        observeFrameChanges()
    }

    // MARK: - Configuration

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        window.minSize = NSSize(width: 220, height: 320)
        setBackgroundLevel()
    }

    private func setBackgroundLevel() {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private func setFloatingLevel() {
        window.level = .floating
    }

    private func installContentView() {
        let root = TimelineView(store: store, clock: clock)
            .frame(minWidth: AppTheme.windowDefaultWidth, minHeight: 320)
            .background(WindowBackground())
        let hosting = NSHostingView(rootView: root)
        window.contentView = hosting
    }

    // MARK: - Public controls

    func show() {
        if window.isVisible { return }
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func isVisible() -> Bool { window.isVisible }

    func bringToFrontTemporarily(duration: TimeInterval = 5) {
        setFloatingLevel()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isForegroundTemporary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self else { return }
            guard self.isForegroundTemporary else { return }
            self.setBackgroundLevel()
            self.isForegroundTemporary = false
        }
    }

    func pinToFrontToggle() {
        if window.level == .floating {
            setBackgroundLevel()
        } else {
            setFloatingLevel()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Frame persistence

    private static func loadSavedFrame() -> NSRect? {
        guard let stored = UserDefaults.standard.string(forKey: "TimeManager.windowFrame") else { return nil }
        let rect = NSRectFromString(stored)
        guard rect.width >= 220, rect.height >= 500 else { return nil }
        return rect
    }

    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = AppTheme.windowDefaultWidth
        let height: CGFloat = screen.height * 0.9
        let x = screen.maxX - width - 24
        let y = screen.minY + (screen.height - height) / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var frameObserver: NSObjectProtocol?

    private func observeFrameChanges() {
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistFrame() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistFrame() }
        }
    }

    private func persistFrame() {
        let rect = window.frame
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: frameDefaultsKey)
    }
}

private struct WindowBackground: View {
    var body: some View {
        Color.clear
    }
}
