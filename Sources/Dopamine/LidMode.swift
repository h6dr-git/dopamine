import Foundation

// Controls `pmset -a disablesleep` — the only switch that stops lid-close
// (clamshell) sleep; no user-space assertion can. Root required: normally via
// the exact-command NOPASSWD sudoers rule install.sh sets up (silent), else an
// admin-password dialog for user-initiated toggles.
enum LidMode {
    // Setter name and getter name differ: you *set* `disablesleep`, but
    // `pmset -g` reports it as `SleepDisabled` (tab-separated), and only
    // lists the line at all while it is 1.
    static var isOn: Bool {
        let out = run("/usr/bin/pmset", ["-g"]).output
        for line in out.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.first?.lowercased() == "sleepdisabled" {
                return fields.dropFirst().first == "1"
            }
        }
        return false
    }

    // interactive=false is the unattended path (timers, quit, self-heal): it
    // must never block on a dialog, so it only tries the silent sudoers route.
    @discardableResult
    static func set(_ on: Bool, interactive: Bool = false) -> Bool {
        let value = on ? "1" : "0"
        if run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]).status == 0 {
            return true
        }
        guard interactive else { return false }
        let script = """
        do shell script "/usr/bin/pmset -a disablesleep \(value)" with administrator privileges \
        with prompt "도파민: 뚜껑 닫기 모드를 \(on ? "켭니다" : "끕니다")."
        """
        return run("/usr/bin/osascript", ["-e", script]).status == 0
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return (127, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
