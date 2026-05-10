import Foundation

final class ADBDeviceMonitor {
    var onUpdate: ((ADBDeviceState) -> Void)?

    private let queue = DispatchQueue(label: "android-monitor.menu.adb-device")
    private var timer: DispatchSourceTimer?
    private var isRefreshing = false
    private var pendingRefresh = false

    func start() {
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.requestRefreshOnQueue()
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
            self?.requestRefreshOnQueue()
        }
    }

    private func requestRefreshOnQueue() {
        guard !isRefreshing else {
            pendingRefresh = true
            return
        }

        isRefreshing = true
        let state = ADBClient.readDeviceState()
        isRefreshing = false

        let shouldRefreshAgain = pendingRefresh
        pendingRefresh = false

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(state)
        }

        if shouldRefreshAgain {
            requestRefreshOnQueue()
        }
    }
}
