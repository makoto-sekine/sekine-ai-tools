import Foundation
import Combine

@MainActor
final class CurrentTimeObserver: ObservableObject {
    @Published private(set) var now: Date = Date()
    private var timer: Timer?

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    func start() {
        stop()
        now = Date()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
