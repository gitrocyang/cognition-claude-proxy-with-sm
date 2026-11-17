import Foundation
import Darwin

struct ServiceSnapshot {
    enum State: String { case running = "运行中", stopped = "已停止", starting = "启动中", stopping = "停止中", error = "异常" }
    let state: State
    let detail: String
    let autoStart: Bool
}

struct ServiceManager {
    static let label = "com.gitrocyang.devin-proxy-manager.proxy"
    static let marker = "DevinProxyManager"
    static let defaults = UserDefaults.standard
    var homeOverride: URL? = nil
    var preferences: UserDefaults = .standard

    var home: URL { homeOverride ?? FileManager.default.homeDirectoryForCurrentUser }
    var agentURL: URL { home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist") }
    var logDirectory: URL { home.appendingPathComponent("Library/Logs/DevinProxyManager") }
    var projectURL: URL? {
        guard let path = preferences.string(forKey: "projectPath"), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    var port: Int {
        let value = preferences.integer(forKey: "port")
        return (1...65535).contains(value) ? value : 8765
    }
    var credentialURL: URL {
        if let path = preferences.string(forKey: "credentialsPath"), !path.isEmpty { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(".local/share/devin/credentials.toml")
    }
    var domain: String { "gui/\(getuid())" }
    var service: String { "\(domain)/\(Self.label)" }

    func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func agent() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: agentURL.path) else { return nil }
        let data = try Data(contentsOf: agentURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == Self.label,
              plist["ManagedBy"] as? String == Self.marker else {
            throw NSError(domain: "DevinProxyManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "同名 LaunchAgent 不属于本管理器，已拒绝修改。"])
        }
        return plist
    }

    func nodeURL() -> URL? {
        let saved = preferences.string(forKey: "nodePath")
        let paths = saved.map { [$0] } ?? ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
        return paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func environmentIssues() -> [String] {
        var issues: [String] = []
        guard let project = projectURL else { return ["请先选择本项目目录。"] }
        if !FileManager.default.fileExists(atPath: project.appendingPathComponent("package.json").path) ||
            !FileManager.default.fileExists(atPath: project.appendingPathComponent("src/server.js").path) ||
            !FileManager.default.fileExists(atPath: project.appendingPathComponent("scripts/managed-server.js").path) {
            issues.append("项目目录缺少代理入口文件。")
        }
        if let node = nodeURL() {
            let (status, output) = run(node.path, ["--version"])
            let major = Int(output.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst().split(separator: ".").first ?? "") ?? 0
            if status != 0 || major < 18 { issues.append("Node.js 版本需为 18 或以上。") }
        } else { issues.append("找不到 Node.js；请设置可执行文件路径。") }
        if !FileManager.default.isReadableFile(atPath: credentialURL.path) {
            issues.append("找不到可读取的 Devin CLI 凭据文件；请先运行 devin auth login。")
        }
        if let listener = listenerPID(), listener != launchPID() {
            issues.append("端口 \(port) 已被 PID \(listener) 占用。")
        }
        return issues
    }

    func launchPID() -> Int32? {
        let (status, output) = run("/bin/launchctl", ["print", service])
        guard status == 0, let range = output.range(of: #"\bpid = (\d+)"#, options: .regularExpression) else { return nil }
        return Int32(output[range].split(separator: " ").last ?? "")
    }

    func loaded() -> Bool { run("/bin/launchctl", ["print", service]).0 == 0 }

    func listenerPID() -> Int32? {
        let (status, output) = run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-t"])
        guard status == 0 else { return nil }
        return Int32(output.split(whereSeparator: \.isNewline).first ?? "")
    }

    func healthy() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var healthy = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let data, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                healthy = body["ok"] as? Bool == true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return healthy
    }

    func snapshot() -> ServiceSnapshot {
        let configured: Bool
        do { configured = try agent() != nil } catch { return .init(state: .error, detail: error.localizedDescription, autoStart: false) }
        let auto = (try? agent())?["RunAtLoad"] as? Bool ?? false
        let pid = launchPID()
        let listener = listenerPID()
        if let listener, listener != pid {
            return .init(state: .error, detail: "端口 \(port) 被其他进程占用（PID \(listener)）；不会终止该进程。", autoStart: auto)
        }
        if let pid {
            if listener == pid && healthy() { return .init(state: .running, detail: "LaunchAgent PID \(pid)", autoStart: auto) }
            return .init(state: .error, detail: "LaunchAgent PID \(pid) 存在，但健康检查未通过。", autoStart: auto)
        }
        return .init(state: .stopped, detail: configured ? "LaunchAgent 已配置，代理未运行。" : "代理未受管理。", autoStart: auto)
    }

    func writeAgent(autoStart: Bool) throws {
        guard let project = projectURL, let node = nodeURL() else {
            throw NSError(domain: "DevinProxyManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "请先设置有效的项目目录与 Node.js 路径。"])
        }
        var env = ["CCP_PORT": String(port), "CCP_MANAGED_LOG_DIR": logDirectory.path]
        if preferences.string(forKey: "credentialsPath") != nil { env["CCP_CREDENTIALS"] = credentialURL.path }
        let plist: [String: Any] = [
            "Label": Self.label, "ManagedBy": Self.marker,
            "ProgramArguments": [node.path, project.appendingPathComponent("scripts/managed-server.js").path],
            "WorkingDirectory": project.path,
            "EnvironmentVariables": env,
            "RunAtLoad": autoStart,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": 5,
            "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"
        ]
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
    }

    func command(_ args: [String], allowedFailure: Bool = false) throws {
        let (status, output) = run("/bin/launchctl", args)
        if status != 0 && !allowedFailure {
            throw NSError(domain: "DevinProxyManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    func start() throws {
        if snapshot().state == .running { return }
        if let pid = listenerPID() { throw NSError(domain: "DevinProxyManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "端口 \(port) 已被 PID \(pid) 占用。请先手动处理原有服务。"]) }
        let issues = environmentIssues()
        if !issues.isEmpty { throw NSError(domain: "DevinProxyManager", code: 4, userInfo: [NSLocalizedDescriptionKey: issues.joined(separator: "\n")]) }
        let auto = (try agent())?["RunAtLoad"] as? Bool ?? false
        if loaded() { try command(["bootout", service]) }
        try writeAgent(autoStart: auto)
        try command(["bootstrap", domain, agentURL.path])
        try command(["kickstart", service])
        for _ in 0..<20 {
            if snapshot().state == .running { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw NSError(domain: "DevinProxyManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "代理未通过健康检查，请查看错误日志。"])
    }

    func stop() throws {
        _ = try agent()
        if loaded() { try command(["bootout", service]) }
        // bootout is scoped to this exact launchd label; never signal a PID found by name.
    }

    func restart() throws { try stop(); try start() }

    func setAutoStart(_ enabled: Bool) throws {
        let current = try agent()
        if !enabled && current == nil { return }
        if enabled {
            let issues = environmentIssues()
            if !issues.isEmpty { throw NSError(domain: "DevinProxyManager", code: 6, userInfo: [NSLocalizedDescriptionKey: issues.joined(separator: "\n")]) }
        }
        let running = snapshot().state == .running
        if running { try stop() }
        try writeAgent(autoStart: enabled)
        if running { try start() }
    }

    func uninstall() throws {
        guard try agent() != nil else { return }
        try stop()
        try FileManager.default.removeItem(at: agentURL)
    }

    func recentLog(_ name: String) -> String {
        let url = logDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return "暂无日志。" }
        return String(decoding: data.suffix(24_000), as: UTF8.self)
    }
}
