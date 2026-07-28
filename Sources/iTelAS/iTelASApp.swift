import AppKit
import SwiftUI
import iTelASCore

private final class ITelASApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let icon: NSImage?
        if let url = Bundle.main.url(forResource: "iTelASIcon", withExtension: "png"),
           let bundledIcon = NSImage(contentsOf: url) {
            icon = bundledIcon
        } else if let url = Bundle.main.url(forResource: "iTelAS", withExtension: "icns"),
                  let bundledIcon = NSImage(contentsOf: url) {
            icon = bundledIcon
        } else {
            icon = Bundle.module.url(forResource: "iTelASIcon", withExtension: "png")
                .flatMap(NSImage.init(contentsOf:))
        }

        guard let icon else { return }
        icon.isTemplate = false
        NSApplication.shared.applicationIconImage = icon
    }
}

@main
struct iTelASApp: App {
    @NSApplicationDelegateAdaptor(ITelASApplicationDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(model)
                .frame(minWidth: 1_100, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_420, height: 900)
        .commands {
            CommandMenu("IBM i") {
                Button("New IBM i Session…") {
                    model.presentNewSession()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                if let profile = model.selectedProfile {
                    Button("Open Another \(profile.name) Terminal") {
                        model.openAdditionalSession(profile)
                    }
                    .keyboardShortcut("t", modifiers: .command)
                }

                Button("Previous Terminal") {
                    model.selectAdjacentTerminalSession(-1)
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model.terminalSessions.count < 2)

                Button("Next Terminal") {
                    model.selectAdjacentTerminalSession(1)
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model.terminalSessions.count < 2)

                Button(model.isCommandPalettePresented ? "Close Command Palette" : "Command Palette") {
                    model.isCommandPalettePresented.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Command Center") {
                    model.selectedTool = .commandCenter
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button(model.isAssistantVisible ? "Hide iTelAS Assist" : "Show iTelAS Assist") {
                    model.isAssistantVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            AISettingsView()
                .environment(model)
                .frame(width: 620, height: 560)
        }
    }
}
