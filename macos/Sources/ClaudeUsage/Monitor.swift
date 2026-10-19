import Foundation
import Observation

/// Runs the bundled monitor.py and polls its state.
///
/// A monitor already serving the current API on the default port is reused, so a second copy
/// never scans the same transcripts; one serving an older API is left alone and ours takes the next port.
@MainActor @Observable
final class Monitor {
    enum Link: Equatable { case starting, live, unreachable }

    private(set) var state: UsageState?
    private(set) var link: Link = .starting
    private(set) var lastUpdate: Date?
    private(set) var problem: String?

    static let apiVersion = 3
    private let ports = [8765, 8766]
    private var port = 8765
    private var process: Process?
    private var failures = 0
    private var timer: Timer?
    var onUpdate: ((UsageState) -> Void)?

    var usage: Usage? { state.map(Usage.init) }

    func start() {
        Task { await connect() }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        process?.terminate()
    }

    func refresh() { Task { await poll() } }

    private func connect() async {
        for p in ports {
            switch await probe(p) {
            case .ours:
                port = p
                await poll()
                return
            case .free:
                port = p
                launch()
                for _ in 0..<60 {  // the first scan of a large history takes a while
                    try? await Task.sleep(for: .milliseconds(500))
                    if await probe(p) == .ours { break }
                    if process?.isRunning == false { break }
                }
                await poll()
                return
            case .other:
                continue
            }
        }
        link = .unreachable
        problem = L("8765 和 8766 端口都被别的程序占用了", "Ports 8765 and 8766 are both taken by other programs")
    }

    private enum Probe { case ours, free, other }

    private func probe(_ p: Int) async -> Probe {
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(p)/api/state")!)
            let v = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["api_version"] as? Int ?? 0
            return v >= Self.apiVersion ? .ours : .other
        } catch let e as URLError where e.code == .cannotConnectToHost {
            return .free
        } catch {
            return .other
        }
    }

    private func launch() {
        guard let script = Bundle.main.url(forResource: "monitor", withExtension: "py", subdirectory: "monitor") else {
            problem = L("app 里找不到 monitor.py", "monitor.py is missing from the app")
            return
        }
        let python = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let python else {
            problem = L("没找到 python3，先装 Xcode 命令行工具", "python3 not found; install the Xcode command line tools")
            return
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude Usage", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let log = support.appendingPathComponent("monitor.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [script.path, "--db", support.appendingPathComponent("state.db").path, "--port", String(port)]
        if let h = try? FileHandle(forWritingTo: log) {
            p.standardOutput = h
            p.standardError = h
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.process = nil }
        }
        do {
            try p.run()
            process = p
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func poll() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/state")!)
            let s = try UsageState.decode(data)
            state = s
            lastUpdate = Date()
            failures = 0
            link = .live
            problem = nil
            onUpdate?(s)
        } catch is DecodingError {
            failures += 1
            problem = L("数据格式对不上，可能是旧版服务", "The data did not parse; the server may be an old version")
            if failures >= 3 { link = .unreachable }
        } catch {
            failures += 1
            if failures >= 3 {
                link = .unreachable
                // Ours stopped: start it again on the same port.
                if process == nil, await probe(port) == .free { launch() }
            }
        }
    }

    /// Records a weekly reading read off claude.ai, which the server uses as its new official base.
    func addReading(_ pct: Double) async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/reading")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-Claude-Usage")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["weekly": pct])
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        await poll()
        return (resp as? HTTPURLResponse)?.statusCode == 204
    }
}
