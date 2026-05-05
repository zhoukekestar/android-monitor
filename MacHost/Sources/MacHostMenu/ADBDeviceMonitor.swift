import Foundation

final class ADBDeviceMonitor {
    var onUpdate: ((ADBDeviceState) -> Void)?

    private let queue = DispatchQueue(label: "android-monitor.menu.adb-device")
    private var timer: DispatchSourceTimer?

    func start() {
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.refreshOnQueue()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            self?.refreshOnQueue()
        }
    }

    private func refreshOnQueue() {
        let state = ADBClient.readDeviceState()
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(state)
        }
    }
}
