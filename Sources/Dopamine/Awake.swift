import Foundation

// Holds the Mac awake by running `caffeinate -dis` (display + idle + system).
// `-w <our pid>` ties the child's lifetime to this app: if the app dies for any
// reason, caffeinate exits with it and the Mac returns to its normal sleep policy.
final class Awake {
    private var process: Process?
    private(set) var startedAt: Date?

    // Fired on the main thread when caffeinate dies while we thought it was on
    // (e.g. killed externally), so the UI can drop back to "off".
    var onUnexpectedExit: (() -> Void)?

    var isOn: Bool { process?.isRunning == true }

    func turnOn() {
        guard !isOn else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-dis", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.process === proc else { return }
                self.process = nil
                self.startedAt = nil
                self.onUnexpectedExit?()
            }
        }
        do {
            try p.run()
            process = p
            startedAt = Date()
        } catch {
            process = nil
            startedAt = nil
        }
    }

    func turnOff() {
        guard let p = process else { return }
        process = nil          // expected exit: detach before signalling
        startedAt = nil
        p.terminationHandler = nil
        p.terminate()
    }
}
