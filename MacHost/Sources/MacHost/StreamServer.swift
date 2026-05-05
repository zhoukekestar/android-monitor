import CoreGraphics
import Foundation
import Network

struct AndroidStreamStats {
    let decodedFrames: Int
    let droppedFrames: Int
    let inputFps: Double
    let bitrateMbps: Double
}

final class StreamServer {
    private let width: Int
    private let height: Int
    private let fps: Int
    private let bitrateMbps: Int
    private let port: UInt16
    private let inputDisplayID: CGDirectDisplayID?
    private let logInputEvents: Bool
    private let queue = DispatchQueue(label: "android-monitor.phase0.server")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var isReady = false
    private var clientHelloReceived = false
    private var sequence: UInt32 = 0
    var onStats: ((AndroidStreamStats) -> Void)?

    init(
        width: Int,
        height: Int,
        fps: Int,
        bitrateMbps: Int,
        port: UInt16,
        inputDisplayID: CGDirectDisplayID? = nil,
        logInputEvents: Bool = false
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateMbps = bitrateMbps
        self.port = port
        self.inputDisplayID = inputDisplayID
        self.logInputEvents = logInputEvents
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 30
            tcp.keepaliveInterval = 10
            tcp.keepaliveCount = 3
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SpikeError.argument("invalid TCP port \(port)")
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[OK] TCP stream server listening on 127.0.0.1:\(self.port)")
                print("     USB setup: adb reverse tcp:\(self.port) tcp:\(self.port)")
            case .failed(let error):
                print("[WARN] TCP listener failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func send(_ frame: EncodedFrame) {
        queue.async { [weak self] in
            guard let self, let connection = self.connection, self.isReady else {
                return
            }

            var packet = Data(capacity: 24 + frame.data.count)
            packet.appendBigEndian(UInt32(0x414D4F4E)) // "AMON"
            packet.append(UInt8(1)) // version
            packet.append(UInt8(2)) // video packet
            packet.appendBigEndian(UInt16(frame.isKeyframe ? 1 : 0))
            packet.appendBigEndian(self.sequence)
            packet.appendBigEndian(frame.presentationTimestampNs)
            packet.appendBigEndian(UInt32(frame.data.count))
            packet.append(frame.data)
            self.sequence &+= 1

            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    print("[WARN] Send failed: \(error)")
                }
            })
        }
    }

    func waitForClientHello(timeoutSeconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while true {
            if queue.sync(execute: { clientHelloReceived }) {
                return true
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                return false
            }

            let slice = min(0.05, remaining)
            if Thread.isMainThread {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: slice))
            } else {
                Thread.sleep(forTimeInterval: slice)
            }
        }
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
        isReady = false
        clientHelloReceived = false
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        isReady = false
        clientHelloReceived = false
        sequence = 0

        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isReady = true
                print("[OK] Android client connected")
                self?.receiveControlMessages(from: newConnection)
                self?.sendConfig()
            case .failed(let error):
                print("[WARN] Android client failed: \(error)")
                self?.isReady = false
            case .cancelled:
                print("[INFO] Android client disconnected")
                self?.isReady = false
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    private func receiveControlMessages(from connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let error {
                print("[WARN] Control receive failed: \(error)")
                return
            }

            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
                self.consumeControlLines(from: &nextBuffer)
            }

            if isComplete {
                return
            }

            self.receiveControlMessages(from: connection, buffer: nextBuffer)
        }
    }

    private func consumeControlLines(from buffer: inout Data) {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else {
                continue
            }

            do {
                let object = try JSONSerialization.jsonObject(with: Data(line), options: [])
                guard let message = object as? [String: Any] else {
                    print("[WARN] Ignoring non-object control message")
                    continue
                }
                handleControlMessage(message)
            } catch {
                let text = String(data: Data(line), encoding: .utf8) ?? "<non-utf8>"
                print("[WARN] Bad control JSON: \(text)")
            }
        }
    }

    private func handleControlMessage(_ message: [String: Any]) {
        let type = message["type"] as? String ?? "<missing>"
        switch type {
        case "client_hello":
            let model = message["model"] as? String ?? "unknown"
            let manufacturer = message["manufacturer"] as? String ?? "unknown"
            let apiLevel = message["api_level"] as? Int ?? -1
            let screenWidth = message["screen_width"] as? Int ?? -1
            let screenHeight = message["screen_height"] as? Int ?? -1
            clientHelloReceived = true
            print("[OK] Android hello: \(manufacturer) \(model), API \(apiLevel), screen \(screenWidth)x\(screenHeight)")
        case "stats":
            let decoded = message["decoded_frames"] as? Int ?? 0
            let dropped = message["dropped_frames"] as? Int ?? 0
            let inputFps = message["input_fps"] as? Double ?? 0
            let bitrate = message["bitrate_mbps"] as? Double ?? 0
            print(String(format: "[INFO] Android stats: decoded=%d dropped=%d input=%.1f fps %.2f Mbps", decoded, dropped, inputFps, bitrate))
            onStats?(
                AndroidStreamStats(
                    decodedFrames: decoded,
                    droppedFrames: dropped,
                    inputFps: inputFps,
                    bitrateMbps: bitrate
                )
            )
        case "error":
            let detail = message["message"] as? String ?? "<no detail>"
            print("[WARN] Android error: \(detail)")
        case "touch":
            handleTouchMessage(message)
        default:
            print("[INFO] Android control \(type): \(message)")
        }
    }

    private func handleTouchMessage(_ message: [String: Any]) {
        let action = message["action"] as? String ?? ""
        guard let x = normalizedDouble(message["x"]),
              let y = normalizedDouble(message["y"]) else {
            return
        }

        if logInputEvents {
            if action == "scroll",
               let deltaX = doubleValue(message["delta_x"]),
               let deltaY = doubleValue(message["delta_y"]) {
                print(String(format: "[INFO] Android input: action=%@ x=%.3f y=%.3f delta_x=%.3f delta_y=%.3f", action, x, y, deltaX, deltaY))
            } else {
                print(String(format: "[INFO] Android input: action=%@ x=%.3f y=%.3f", action, x, y))
            }
        }

        guard let inputDisplayID else {
            return
        }

        let bounds = CGDisplayBounds(inputDisplayID)
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let point = CGPoint(
            x: bounds.minX + CGFloat(x) * bounds.width,
            y: bounds.minY + CGFloat(y) * bounds.height
        )
        if action == "scroll" {
            guard let deltaX = doubleValue(message["delta_x"]),
                  let deltaY = doubleValue(message["delta_y"]) else {
                return
            }
            postScrollEvent(
                point: point,
                deltaX: CGFloat(deltaX) * bounds.width,
                deltaY: CGFloat(deltaY) * bounds.height
            )
            return
        }
        postMouseEvent(action: action, point: point)
    }

    private func normalizedDouble(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return min(1, max(0, value))
        }
        if let value = value as? NSNumber {
            return min(1, max(0, value.doubleValue))
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private func postMouseEvent(action: String, point: CGPoint) {
        let eventType: CGEventType
        switch action {
        case "down":
            eventType = .leftMouseDown
        case "move":
            eventType = .leftMouseDragged
        case "up", "cancel":
            eventType = .leftMouseUp
        default:
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postScrollEvent(point: CGPoint, deltaX: CGFloat, deltaY: CGFloat) {
        let horizontal = Int32(max(-2_000, min(2_000, -deltaX)))
        let vertical = Int32(max(-2_000, min(2_000, -deltaY)))
        guard horizontal != 0 || vertical != 0 else {
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            return
        }
        event.location = point
        event.post(tap: .cghidEventTap)
    }

    private func sendConfig() {
        guard let connection else {
            return
        }

        let config: [String: Any] = [
            "type": "stream_config",
            "codec": "h264",
            "format": "annexb",
            "width": width,
            "height": height,
            "fps": fps,
            "bitrate_mbps": bitrateMbps
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: config, options: []),
              var line = String(data: json, encoding: .utf8)?.data(using: .utf8) else {
            return
        }

        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { error in
            if let error {
                print("[WARN] Config send failed: \(error)")
            }
        })
    }
}
