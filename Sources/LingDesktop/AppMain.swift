import AppKit
import SwiftUI
import CoreGraphics

final class AssistantPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let settings = SettingsStore()
    private lazy var model = AssistantModel(settings: settings)
    private let hotKey = GlobalHotKey()
    private let capture = ScreenCapture()
    private var assistantPanel: AssistantPanel?
    private var settingsWindow: NSWindow?
    private var captureTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder.circle", accessibilityDescription: "百灵视觉助手")
        statusItem.button?.toolTip = "百灵视觉助手 · ⌘⇧A 框选提问"
        let menu = NSMenu()
        let captureItem = menu.addItem(withTitle: "截图提问", action: #selector(startCapture), keyEquivalent: "a")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(withTitle: "打开提问", action: #selector(showAssistant), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出百灵视觉助手", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        hotKey.onPress = { [weak self] in
            Task { @MainActor in self?.startCapture() }
        }
        let result = hotKey.register()
        if result != noErr {
            DispatchQueue.main.async { [weak self] in
                self?.alert("快捷键注册失败", detail: "⌘⇧A 可能已被其他应用占用（错误 \(result)）。仍可通过菜单栏的「截图提问」使用。")
            }
        }
        if settings.apiKey.isEmpty || settings.loadError != nil { showSettings() }
        else { showAssistant() }
    }

    @objc func showAssistant() {
        if assistantPanel == nil {
            let panel = AssistantPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 670),
                                       styleMask: [.titled, .closable, .resizable],
                                       backing: .buffered, defer: false)
            panel.title = "百灵视觉助手"
            panel.titlebarAppearsTransparent = true
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 440, height: 600)
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: AssistantView(model: model,
                capture: { [weak self] in self?.startCapture() },
                openSettings: { [weak self] in self?.showSettings() }))
            panel.center()
            assistantPanel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        assistantPanel?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "百灵设置"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings,
                close: { [weak self] in self?.settingsWindow?.orderOut(nil) }))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出百灵视觉助手", action: #selector(quit), keyEquivalent: "q").target = self
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)
        // A manually bootstrapped AppKit app needs an Edit menu for standard
        // keyboard paste/copy shortcuts in SwiftUI text fields and editors.
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc func startCapture() {
        guard captureTask == nil else { return }
        model.cancel()
        assistantPanel?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        captureTask = Task {
            defer { captureTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(180))
                if let data = try await capture.selectRegion() {
                    model.setCapture(data)
                    showAssistant()
                }
            } catch CaptureError.permission {
                NSApp.activate(ignoringOtherApps: true)
                let dialog = NSAlert()
                dialog.messageText = "允许百灵框选屏幕"
                dialog.informativeText = CaptureError.permission.localizedDescription
                dialog.addButton(withTitle: "打开系统设置")
                dialog.addButton(withTitle: "稍后")
                if dialog.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            } catch is CancellationError {
                return
            } catch {
                alert("无法截图", detail: error.localizedDescription)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === assistantPanel { model.cancel() }
    }

    private func alert(_ title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let dialog = NSAlert()
        dialog.messageText = title
        dialog.informativeText = detail
        dialog.addButton(withTitle: "好")
        dialog.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        model.cancel()
        capture.cancel()
        captureTask?.cancel()
    }
}

@main
enum LingDesktopMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
