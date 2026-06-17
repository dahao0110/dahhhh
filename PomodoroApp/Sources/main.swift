import SwiftUI
import AppKit
import UserNotifications
import AVFoundation

// MARK: - App Entry
@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var vm = TimerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 420, maxWidth: 520, minHeight: 600, maxHeight: 700)
                .onAppear { NSWindow.allowsAutomaticWindowTabbing = false }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
            CommandMenu("计时器") {
                Button("开始 / 暂停") { vm.toggle() }.keyboardShortcut(.space, modifiers: [])
                Button("重置") { vm.reset() }.keyboardShortcut("r", modifiers: [])
                Button("跳过") { vm.skip() }.keyboardShortcut("s", modifiers: [])
                Divider()
                Button("专注模式") { vm.mode = .work }.keyboardShortcut("1", modifiers: [])
                Button("短休息") { vm.mode = .shortBreak }.keyboardShortcut("2", modifiers: [])
                Button("长休息") { vm.mode = .longBreak }.keyboardShortcut("3", modifiers: [])
            }
        }
    }
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        if let window = NSApplication.shared.windows.first {
            window.title = "Pomodoro"
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.center()
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

// MARK: - ViewModel
enum TimerMode: String, CaseIterable, Codable {
    case work = "专注"
    case shortBreak = "短休息"
    case longBreak = "长休息"

    var icon: String { switch self {
        case .work: return "🍅"
        case .shortBreak: return "☕"
        case .longBreak: return "🌿"
    }}

    var label: String { switch self {
        case .work: return "专注中"
        case .shortBreak: return "休息中"
        case .longBreak: return "长休息中"
    }}

    var idleLabel: String { switch self {
        case .work: return "准备开始"
        case .shortBreak: return "准备休息"
        case .longBreak: return "准备长休息"
    }}
}

@MainActor
final class TimerViewModel: ObservableObject {
    @Published var mode: TimerMode = .work { didSet { if oldValue != mode { resetToMode() } } }
    @Published var remaining: Int = 25 * 60
    @Published var total: Int = 25 * 60
    @Published var isRunning = false
    @Published var pomodoros: Int = 0
    @Published var showCongrats = false

    struct Settings: Codable {
        var workMin: Int = 25
        var shortBreakMin: Int = 5
        var longBreakMin: Int = 15
    }
    @Published var settings = Settings() { didSet { save(); if !isRunning { resetToMode() } } }

    private var timer: Timer?
    private var player: AVAudioPlayer?

    init() { load() }

    func toggle() {
        if isRunning { pause() } else { start() }
    }

    func start() {
        if remaining <= 0 { resetToMode() }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remaining = total
    }

    func skip() {
        pause()
        transitionFromCurrent()
    }

    private func tick() {
        if remaining > 0 {
            remaining -= 1
        }
        if remaining <= 0 {
            complete()
        }
    }

    private func complete() {
        pause()
        playSound()
        sendNotification()
        if mode == .work {
            pomodoros += 1
            showCongrats = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.showCongrats = false
            }
            mode = (pomodoros % 4 == 0) ? .longBreak : .shortBreak
        } else {
            mode = .work
        }
        resetToMode()
    }

    private func transitionFromCurrent() {
        if mode == .work {
            mode = (pomodoros > 0 && (pomodoros + 1) % 4 == 0) ? .longBreak : .shortBreak
        } else {
            mode = .work
        }
        resetToMode()
    }

    private func resetToMode() {
        total = durationFor(mode)
        remaining = total
        save()
    }

    private func durationFor(_ m: TimerMode) -> Int {
        switch m {
        case .work: return settings.workMin * 60
        case .shortBreak: return settings.shortBreakMin * 60
        case .longBreak: return settings.longBreakMin * 60
        }
    }

    private func playSound() {
        guard let url = Bundle.main.url(forResource: "complete", withExtension: "aiff") else {
            // fallback: system beep
            NSSound.beep()
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        if mode == .work {
            content.title = "🍅 番茄完成！"
            content.body = "太棒了，休息一下吧！"
        } else {
            content.title = "⏰ 休息结束！"
            content.body = "准备好开始新的番茄了吗？"
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func save() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("pomodoro_state.json")
        let data: [String: Any] = [
            "pomodoros": pomodoros,
            "mode": mode.rawValue,
            "workMin": settings.workMin,
            "shortMin": settings.shortBreakMin,
            "longMin": settings.longBreakMin,
            "today": ISO8601DateFormatter().string(from: Date())
        ]
        if let json = try? JSONSerialization.data(withJSONObject: data) {
            try? json.write(to: path)
        }
    }

    private func load() {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let path = dir.appendingPathComponent("pomodoro_state.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let mins = json["workMin"] as? Int { settings.workMin = mins }
        if let mins = json["shortMin"] as? Int { settings.shortBreakMin = mins }
        if let mins = json["longMin"] as? Int { settings.longBreakMin = mins }
        if let raw = json["mode"] as? String, let m = TimerMode(rawValue: raw) { mode = m }
        if let p = json["pomodoros"] as? Int, let todayStr = json["today"] as? String {
            let today = ISO8601DateFormatter().string(from: Date())
            pomodoros = (todayStr.prefix(10) == today.prefix(10)) ? p : 0
        }
        resetToMode()
    }
}

// MARK: - Content View
struct ContentView: View {
    @EnvironmentObject var vm: TimerViewModel

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [Color(white: 0.10), Color(white: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 标题
                Text("Pomodoro")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 12)

                Spacer(minLength: 16)

                // 模式选择器
                ModePicker()
                    .padding(.horizontal)
                    .padding(.bottom, 28)

                // 计时器圆环
                TimerView()
                    .frame(width: 280, height: 280)
                    .padding(.bottom, 28)

                // 控制按钮
                HStack(spacing: 16) {
                    CircleButton(icon: "arrow.counterclockwise", label: "重置") {
                        vm.reset()
                    }

                    PlayButton()

                    CircleButton(icon: "forward.end.fill", label: "跳过") {
                        vm.skip()
                    }
                }
                .padding(.bottom, 20)

                // 番茄计数
                TomatoDots()
                    .padding(.bottom, 6)

                Text("今日已完成 \(vm.pomodoros) 个番茄")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))

                // 音效测试
                Button("🔔 测试提示音") {
                    NSSound.beep()
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
                .buttonStyle(.plain)
                .padding(.top, 12)

                Spacer(minLength: 12)

                // 时长设置
                SettingsRow()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
            .overlay(alignment: .top) {
                // 完成动画
                if vm.showCongrats {
                    CongratOverlay()
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: vm.showCongrats)
    }
}

// MARK: - Mode Picker
struct ModePicker: View {
    @EnvironmentObject var vm: TimerViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimerMode.allCases, id: \.self) { mode in
                Button {
                    if vm.isRunning { vm.pause() }
                    vm.mode = mode
                } label: {
                    Text("\(mode.icon) \(mode.rawValue)")
                        .font(.system(size: 13, weight: vm.mode == mode ? .semibold : .regular))
                        .foregroundColor(vm.mode == mode ? .white : .white.opacity(0.45))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(
                            vm.mode == mode
                                ? RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.12))
                                : RoundedRectangle(cornerRadius: 9).fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Timer Ring View
struct TimerView: View {
    @EnvironmentObject var vm: TimerViewModel
    @State private var pulse = false

    private let ringSize: CGFloat = 260
    private let ringWidth: CGFloat = 10

    private var progress: Double {
        vm.total > 0 ? Double(vm.remaining) / Double(vm.total) : 1
    }

    private var accentColor: Color {
        if vm.mode != .work { return .green }
        if progress > 0.66 { return .red }
        if progress > 0.33 { return .orange }
        return .yellow
    }

    var body: some View {
        ZStack {
            // 外发光
            Circle()
                .stroke(accentColor.opacity(0.15), lineWidth: ringWidth * 2.5)
                .frame(width: ringSize + 20, height: ringSize + 20)
                .blur(radius: vm.isRunning || vm.remaining != vm.total ? 10 : 0)
                .scaleEffect(pulse ? 1.05 : 1.0)
                .opacity(vm.isRunning ? 0.7 : 0.2)

            // 背景圆环
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: ringWidth)
                .frame(width: ringSize, height: ringSize)

            // 进度圆环
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            accentColor.opacity(0.6),
                            accentColor,
                            accentColor.opacity(0.8)
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)

            // 时间显示
            VStack(spacing: 4) {
                Text(timeString(vm.remaining))
                    .font(.system(size: 52, weight: .light, design: .monospaced))
                    .foregroundColor(.white)

                Text(vm.isRunning ? vm.mode.label : vm.mode.idleLabel)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .onChange(of: vm.isRunning) { _, running in
            if running { withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }}
            if !running { pulse = false }
        }
    }

    func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Buttons
struct PlayButton: View {
    @EnvironmentObject var vm: TimerViewModel

    var body: some View {
        Button(action: { vm.toggle() }) {
            ZStack {
                Circle()
                    .fill(vm.mode != .work ? Color.green : Color.red)
                    .frame(width: 64, height: 64)
                    .shadow(color: (vm.mode != .work ? Color.green : Color.red).opacity(0.4),
                            radius: 12, y: 4)

                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    .frame(width: 64, height: 64)

                Image(systemName: vm.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .offset(x: vm.isRunning ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(vm.isRunning ? 1.0 : 1.0)
    }
}

struct CircleButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tomato Dots
struct TomatoDots: View {
    @EnvironmentObject var vm: TimerViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<8, id: \.self) { i in
                ZStack {
                    Circle()
                        .fill(i < min(vm.pomodoros, 8) ? Color.red.opacity(0.5) : Color.white.opacity(0.08))
                        .frame(width: 16, height: 16)
                    if i < vm.pomodoros {
                        Text("🍅")
                            .font(.system(size: 8))
                    }
                }
            }
            if vm.pomodoros > 8 {
                Text("+\(vm.pomodoros - 8)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}

// MARK: - Settings
struct SettingsRow: View {
    @EnvironmentObject var vm: TimerViewModel

    var body: some View {
        HStack(spacing: 18) {
            SettingField(icon: "🍅", label: "专注", value: $vm.settings.workMin, range: 1...60)
            SettingField(icon: "☕", label: "短休", value: $vm.settings.shortBreakMin, range: 1...30)
            SettingField(icon: "🌿", label: "长休", value: $vm.settings.longBreakMin, range: 1...60)
        }
    }
}

struct SettingField: View {
    let icon: String
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text(icon).font(.system(size: 12))
            Text(label).font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .scaleEffect(0.7)
            Text("\(value)分")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Congrat Overlay
struct CongratOverlay: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            Text("🍅")
                .font(.system(size: 48))
            Text("番茄完成！")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("干得漂亮，休息一下吧")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1
                opacity = 1
            }
        }
    }
}
