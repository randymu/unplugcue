// Copyright (c) 2026 randymu
// Licensed under the UnplugCue Free Use and Non-Sale License 1.0.
import SwiftUI

@main
struct LaCieSafeOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("UnplugCue", id: "main") {
            MainView(model: model)
                .frame(minWidth: 660, idealWidth: 720, minHeight: 620, idealHeight: 740)
        }
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 UnplugCue") { AppIdentity.showAbout() }
            }
        }

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--diagnostics"), args.indices.contains(flag + 1) {
            let path = args[flag + 1]
            Task {
                do {
                    let disks = try await DiskService().discover()
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(disks).write(to: URL(fileURLWithPath: path), options: .atomic)
                } catch {
                    try? Data(error.localizedDescription.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
                }
                NSApp.terminate(nil)
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}
