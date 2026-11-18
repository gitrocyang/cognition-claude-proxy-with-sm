import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class ManagerModel: ObservableObject {
    @Published var snapshot = ServiceSnapshot(state: .stopped, detail: "正在检查…", autoStart: false)
    @Published var busy = false
    @Published var notice = ""
    @Published var logText = ""
    @Published var showingLog = false
    @Published var projectPath = ServiceManager.defaults.string(forKey: "projectPath") ?? ""
    @Published var nodePath = ServiceManager.defaults.string(forKey: "nodePath") ?? ""
    @Published var credentialsPath = ServiceManager.defaults.string(forKey: "credentialsPath") ?? ""
    @Published var portText = String(ServiceManager.defaults.integer(forKey: "port") == 0 ? 8765 : ServiceManager.defaults.integer(forKey: "port"))
    @Published var appLogin = SMAppService.mainApp.status == .enabled
    private let manager = ServiceManager()
    private let snapshotProvider: () -> ServiceSnapshot
    private var refreshTimer: Timer?

    init(snapshotProvider: @escaping () -> ServiceSnapshot = { ServiceManager().snapshot() },
         pollInterval: TimeInterval = 5) {
        self.snapshotProvider = snapshotProvider
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    func refresh() {
        guard !busy else { return }
        let snapshotProvider = self.snapshotProvider
        Task.detached {
            let result = snapshotProvider()
            await MainActor.run { self.snapshot = result }
        }
    }

    func perform(_ name: String, _ action: @escaping () throws -> Void) {
        guard !busy else { return }
        busy = true
        notice = ""
        snapshot = .init(state: name == "停止" ? .stopping : .starting, detail: "正在\(name)…", autoStart: snapshot.autoStart)
        Task.detached {
            let failure: String?
            do { try action(); failure = nil } catch { failure = error.localizedDescription }
            let result = ServiceManager().snapshot()
            await MainActor.run {
                self.snapshot = result
                self.notice = failure ?? ""
                self.busy = false
            }
        }
    }

    func saveSettings() {
        let path = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(portText), (1...65535).contains(port) else { notice = "端口需为 1–65535。"; return }
        ServiceManager.defaults.set(path, forKey: "projectPath")
        ServiceManager.defaults.set(nodePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : nodePath, forKey: "nodePath")
        ServiceManager.defaults.set(credentialsPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : credentialsPath, forKey: "credentialsPath")
        ServiceManager.defaults.set(port, forKey: "port")
        notice = "设置已保存；运行中的服务需重启才会应用。"
        refresh()
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { projectPath = url.path; saveSettings() }
    }

    func showLog(_ name: String) {
        logText = manager.recentLog(name)
        showingLog = true
    }

    func setAppLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            appLogin = SMAppService.mainApp.status == .enabled
        } catch { notice = "管理器登录项设置失败：\(error.localizedDescription)" }
    }
}

struct MenuContent: View {
    @ObservedObject var model: ManagerModel
    private var symbol: String {
        switch model.snapshot.state {
        case .running: "circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .starting, .stopping: "circle.dotted"
        case .stopped: "circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Devin Proxy Manager").font(.headline)
            Label("代理\(model.snapshot.state.rawValue)", systemImage: symbol)
                .foregroundStyle(model.snapshot.state == .running ? .green : model.snapshot.state == .error ? .red : .primary)
            Text(model.snapshot.detail).font(.caption).foregroundStyle(.secondary)
            Text("服务地址  127.0.0.1:\(ServiceManager().port)").font(.caption)
            HStack {
                Button("启动") { model.perform("启动") { try ServiceManager().start() } }
                    .disabled(model.busy || model.snapshot.state == .running)
                Button("停止") { model.perform("停止") { try ServiceManager().stop() } }
                    .disabled(model.busy || !(model.snapshot.state == .running || model.snapshot.detail.contains("LaunchAgent PID")))
                Button("重启") { model.perform("重启") { try ServiceManager().restart() } }
                    .disabled(model.busy || model.snapshot.state != .running)
            }
            Toggle("登录时自动启动代理", isOn: Binding(
                get: { model.snapshot.autoStart },
                set: { value in model.perform("设置") { try ServiceManager().setAutoStart(value) } }
            )).disabled(model.busy || model.projectPath.isEmpty)
            Toggle("登录时打开管理器", isOn: Binding(
                get: { model.appLogin }, set: { model.setAppLogin($0) }
            ))
            Divider()
            TextField("项目目录", text: $model.projectPath).textFieldStyle(.roundedBorder)
            Button("选择项目目录…") { model.chooseProject() }
            TextField("Node.js 绝对路径（留空自动检测）", text: $model.nodePath).textFieldStyle(.roundedBorder)
            TextField("Devin 凭据文件路径（可选）", text: $model.credentialsPath).textFieldStyle(.roundedBorder)
            TextField("代理端口", text: $model.portText).textFieldStyle(.roundedBorder)
            Button("保存设置") { model.saveSettings() }
            Divider()
            Button("查看最近运行日志") { model.showLog("runtime.log") }
            Button("查看错误日志") { model.showLog("error.log") }
            Button("在 Finder 中打开日志目录") { NSWorkspace.shared.open(ServiceManager().logDirectory) }
            Button("检查运行环境") {
                model.perform("检查") {
                    let issues = ServiceManager().environmentIssues()
                    if !issues.isEmpty { throw NSError(domain: "DevinProxyManager", code: 1, userInfo: [NSLocalizedDescriptionKey: issues.joined(separator: "\n")]) }
                }
            }
            Button("刷新状态") { model.refresh() }
            Button("卸载本管理器的代理服务") { model.perform("卸载") { try ServiceManager().uninstall() } }
            if !model.notice.isEmpty { Text(model.notice).font(.caption).foregroundStyle(.red) }
            Divider()
            Button("退出管理器") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 330)
        .popover(isPresented: $model.showingLog) {
            ScrollView { Text(model.logText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                .frame(width: 600, height: 400)
        }
    }
}

struct MenuGlyph: View {
    let state: ServiceSnapshot.State
    private static let base: NSImage = {
        guard let url = Bundle.module.url(forResource: "MenuGlyph", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
    private static func icon(for state: ServiceSnapshot.State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: 2, width: 16, height: 16))
            let dot = NSBezierPath(ovalIn: NSRect(x: 12, y: 0, width: 5, height: 5))
            NSColor.black.set()
            switch state {
            case .running: dot.fill()
            case .stopped: dot.lineWidth = 1.4; dot.stroke()
            case .starting, .stopping: dot.lineWidth = 2; dot.stroke()
            case .error:
                let diamond = NSBezierPath()
                diamond.move(to: NSPoint(x: 14.5, y: 5.5))
                diamond.line(to: NSPoint(x: 17.5, y: 2.5))
                diamond.line(to: NSPoint(x: 14.5, y: -0.5))
                diamond.line(to: NSPoint(x: 11.5, y: 2.5))
                diamond.close()
                diamond.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    var body: some View {
        Image(nsImage: Self.icon(for: state))
            .accessibilityLabel("代理\(state.rawValue)")
    }
}

@main
struct DevinProxyManagerApp: App {
    @StateObject private var model = ManagerModel()
    init() {
        if CommandLine.arguments.contains("--unregister-login-item") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
    }
    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuGlyph(state: model.snapshot.state)
        }
        .menuBarExtraStyle(.window)
    }
}
