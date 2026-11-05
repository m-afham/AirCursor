import AppKit
import SwiftUI

@main
struct AirCursorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = AppController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(controller)
                .environmentObject(controller.pairing)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("AirCursor Controls", id: WindowID.controls) {
            MenuContentView(isControlWindow: true)
                .environmentObject(controller)
                .environmentObject(controller.pairing)
                .onAppear { controller.windowVisibilityChanged() }
                .onDisappear { controller.windowVisibilityChanged() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("AirCursor", id: WindowID.main) {
            MainWindowView()
                .environmentObject(controller)
                .environmentObject(controller.pairing)
                .frame(minWidth: 760, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 620)
        .defaultLaunchBehavior(.suppressed)

        // First launch opens the guided tour; afterwards AirCursor lives in the menu bar.
        Window("Welcome to AirCursor", id: WindowID.tour) {
            TourView()
                .environmentObject(controller)
                .environmentObject(controller.pairing)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(AppController.shared.needsSetup || DebugSnapshot.directory != nil ? .presented : .suppressed)
    }
}

/// The menu bar icon. It's always alive, so it also hands AppController a way to
/// open SwiftUI windows from non-view code.
private struct MenuBarLabel: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(controller.controlStatus.label, systemImage: controller.menuBarSymbol)
            .labelStyle(.titleAndIcon)
            .help("AirCursor: \(controller.statusText). \(HotKey.controls.display) opens controls.")
            .onAppear {
                controller.windowOpener = { id in openWindow(id: id) }
            }
    }
}

enum WindowID {
    static let controls = "controls"
    static let main = "main"
    static let tour = "tour"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppController.shared.start()
            DebugSnapshot.runIfRequested()
            DebugProbe.runIfRequested()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppController.shared.shutdown() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { AppController.shared.showControls() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
