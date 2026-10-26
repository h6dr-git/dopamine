import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let awake = Awake()
    private var lidOn = false                 // our intent: we set disablesleep=1
    private var onSince: Date?
    private var offDeadline: Date?
    private var offTimer: Timer?
    private var tickTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    // 허브용 옵션: 로그인(=앱 시작)할 때 자동으로 켜기. 맥마다 따로 저장된다
    // (UserDefaults, 도메인 com.akf0526.dopamine) — 늘 켜 둘 허브 맥에서만 체크.
    private static let autoOnKey = "autoOnAtLogin"
    private var autoOnAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoOnKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoOnKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Self-heal: a crash/hard kill can leave disablesleep=1 behind. Dopamine
        // owns that flag on this Mac and always starts OFF — unless 자동 켜기 is
        // checked, in which case a leftover 1 is the wanted state and is adopted.
        // Launch-time only — pmset run manually mid-session is never touched.
        if LidMode.isOn {
            if autoOnAtLogin {
                lidOn = true
            } else {
                LidMode.set(false)
                if LidMode.isOn {             // couldn't clear (sudoers 없음) — show the truth
                    lidOn = true
                }
            }
        }

        awake.onUnexpectedExit = { [weak self] in self?.render() }

        // Scriptable controls + clean SIGTERM. Cocoa doesn't run
        // applicationWillTerminate on a bare SIGTERM (launchctl bootout,
        // logout), and disablesleep would linger until the next launch.
        installSignal(SIGUSR1) { [weak self] in self?.toggle() }          // pkill -USR1 -x Dopamine
        installSignal(SIGUSR2) { [weak self] in self?.turnOn(for: 3600) } // pkill -USR2 -x Dopamine
        installSignal(SIGTERM) { [weak self] in
            self?.turnOff(interactive: false)
            NSApp.terminate(nil)
        }

        // 허브용 자동 켜기: 로그인 직후라 암호 창은 띄우지 않는다(sudoers 무인 경로만).
        // 실패하면(규칙 없음) 평소처럼 꺼진 채로 시작.
        if autoOnAtLogin {
            turnOn(for: nil, interactive: false)
        }

        render()
    }

    func applicationWillTerminate(_ notification: Notification) {
        turnOff(interactive: false)
    }

    private func installSignal(_ sig: Int32, handler: @escaping () -> Void) {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler(handler: handler)
        src.resume()
        signalSources.append(src)
    }

    // MARK: - 상태 전환

    private var isOn: Bool { lidOn || awake.isOn }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggle()
        }
    }

    @objc private func toggle() {
        if isOn { turnOff(interactive: true) } else { turnOn(for: nil) }
    }

    @objc private func turnOnInfinite() { turnOn(for: nil) }

    @objc private func turnOnTimed(_ sender: NSMenuItem) { turnOn(for: TimeInterval(sender.tag)) }

    @objc private func turnOffFromMenu() { turnOff(interactive: true) }

    @objc private func quit() { NSApp.terminate(nil) }    // willTerminate가 원복

    // 체크하면 지금 바로 켜고, 이후 로그인(재시동 포함)할 때마다 자동으로 켠다.
    // 체크 해제는 다음 로그인부터 적용 — 지금 켜진 상태는 그대로 둔다(끄기는 클릭).
    @objc private func toggleAutoOn() {
        autoOnAtLogin.toggle()
        if autoOnAtLogin && !isOn {
            turnOn(for: nil)
        }
        render()
    }

    // All-or-nothing: if disablesleep can't be set (password cancelled), stay
    // fully OFF — a filled pill must always mean "lid-close safe".
    private func turnOn(for seconds: TimeInterval?, interactive: Bool = true) {
        guard LidMode.set(true, interactive: interactive) else { render(); return }
        lidOn = true
        if onSince == nil { onSince = Date() }
        awake.turnOn()
        schedule(seconds)
        render()
    }

    private func turnOff(interactive: Bool) {
        awake.turnOff()
        if lidOn, LidMode.set(false, interactive: interactive) {
            lidOn = false
        }
        if !lidOn { onSince = nil }           // clear 실패 시엔 켜짐으로 계속 표시
        schedule(nil)
        render()
    }

    private func schedule(_ seconds: TimeInterval?) {
        offTimer?.invalidate(); offTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        offDeadline = nil
        guard let seconds else { return }
        offDeadline = Date().addingTimeInterval(seconds)
        let off = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.turnOff(interactive: false)  // unattended: silent path only
        }
        off.tolerance = 5
        offTimer = off
        let tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.render()                     // 툴팁의 남은 시간 갱신
        }
        tick.tolerance = 10
        tickTimer = tick
    }

    // MARK: - 표시

    private func render() {
        statusItem.button?.image = Self.icon(on: isOn)
        var tip = isOn ? "도파민 켜짐 — 뚜껑 닫아도 안 잠듦" : "도파민 꺼짐 — 평소대로 잠듦"
        if isOn, let d = offDeadline { tip += " · \(Self.hhmm(d))까지" }
        if autoOnAtLogin { tip += " · 로그인하면 자동 켜기" }
        tip += isOn ? " (클릭: 끄기)" : " (클릭: 켜기)"
        statusItem.button?.toolTip = tip
    }

    private static func icon(on: Bool) -> NSImage {
        let desc = on ? "도파민 켜짐" : "도파민 꺼짐"
        for name in on ? ["pill.fill", "bolt.fill"] : ["pill", "bolt"] {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: desc) {
                let sized = img.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? img
                sized.isTemplate = true
                return sized
            }
        }
        // No SF Symbol available: draw a letter so the item is still visible.
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let s = NSAttributedString(string: "D", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: on ? .heavy : .regular),
                .foregroundColor: NSColor.black,
            ])
            let size = s.size()
            s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
        img.isTemplate = true
        return img
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        add(disabled: statusLine(), to: menu)
        if isOn, let d = offDeadline {
            add(disabled: "⏱ \(remainingText(to: d)) 남음 — \(Self.hhmm(d))에 자동 꺼짐", to: menu)
        }
        menu.addItem(.separator())

        if isOn {
            addItem("끄기", #selector(turnOffFromMenu), to: menu)
        } else {
            addItem("켜기 (끌 때까지)", #selector(turnOnInfinite), to: menu)
        }
        addItem("1시간만 켜기", #selector(turnOnTimed(_:)), to: menu).tag = 3600
        addItem("3시간만 켜기", #selector(turnOnTimed(_:)), to: menu).tag = 10800

        menu.addItem(.separator())
        let autoItem = addItem("로그인하면 자동 켜기 (허브용)", #selector(toggleAutoOn), to: menu)
        autoItem.state = autoOnAtLogin ? .on : .off

        menu.addItem(.separator())
        add(disabled: "⚠️ 충전기 없어도 동작 — 켠 채 가방에 넣지만 말 것 (발열)", to: menu)
        menu.addItem(.separator())
        addItem("도파민 종료", #selector(quit), to: menu, key: "q")

        // Transient menu: attach only while it tracks, so plain clicks keep toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func statusLine() -> String {
        guard isOn else { return "꺼짐 — 평소대로 잠듦" }
        if let t = onSince { return "켜짐 — \(Self.hhmm(t))부터 뚜껑 닫아도 안 잠듦" }
        return "켜짐 — 뚜껑 닫아도 안 잠듦"
    }

    private func remainingText(to d: Date) -> String {
        let m = max(0, Int(d.timeIntervalSinceNow / 60))
        return m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분"
    }

    private static func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "a h:mm"
        return f.string(from: d)
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func add(disabled title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }
}
