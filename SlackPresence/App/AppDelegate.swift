import SwiftUI
import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenuItem: NSMenuItem?

    // State
    private let appState = AppState()
    private let configState = ConfigState()

    // Windows
    private var scheduleWindow: NSWindow?
    private var statusScheduleWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var tokenHelpWindow: NSWindow?
    private var debugWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from dock
        NSApp.setActivationPolicy(.accessory)

        // Set up menu bar
        setupMenuBar()

        // Subscribe to notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openTokenHelp),
            name: .openTokenHelp,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIconUpdateNotification),
            name: .updateMenuBarIcon,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openScheduleEditor),
            name: .openScheduleEditor,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openStatusSchedule),
            name: .openStatusSchedule,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openWelcome),
            name: .openWelcome,
            object: nil
        )

        // Request microphone permission for Webex call detection
        requestMicrophonePermission()

        // Start the schedule manager
        ScheduleManager.shared.start(appState: appState, configState: configState)

        // Show welcome screen on first run
        let config = ConfigManager.shared.loadConfig()
        if !config.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openWelcome()
            }
        }
    }

    private func requestMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[MicPermission] Current status: \(status.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")

        switch status {
        case .authorized:
            print("[MicPermission] Already authorized")
        case .notDetermined:
            print("[MicPermission] Not determined - requesting access...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("[MicPermission] Request result: \(granted ? "granted" : "denied")")
            }
        case .denied, .restricted:
            print("[MicPermission] Denied or restricted - showing alert")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Microphone Access Required"
                alert.informativeText = "SlackPresence needs microphone access to detect calls. Please enable it in System Settings → Privacy & Security → Microphone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")

                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
        @unknown default:
            print("[MicPermission] Unknown status")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScheduleManager.shared.stop()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem?.button != nil {
            updateMenuBarIcon()

            // Start continuous observation of icon state
            startIconObservation()
        }

        // Create menu
        let menu = NSMenu()
        menu.delegate = self

        // Status display
        statusMenuItem = NSMenuItem(title: "Status: \(appState.statusText)", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        menu.addItem(statusMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // Quick actions - Presence
        menu.addItem(NSMenuItem(title: "Set Active", action: #selector(forceActive), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Set Away", action: #selector(forceAway), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Resume Schedule", action: #selector(resumeSchedule), keyEquivalent: "r"))

        menu.addItem(NSMenuItem.separator())

        // Quick actions - Call Override
        menu.addItem(NSMenuItem(title: "Set In Call", action: #selector(setInCall), keyEquivalent: "m"))
        let clearInCallItem = NSMenuItem(title: "Clear In Call", action: #selector(clearInCall), keyEquivalent: "M")
        clearInCallItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(clearInCallItem)

        menu.addItem(NSMenuItem.separator())

        // Windows
        menu.addItem(NSMenuItem(title: "Edit Schedule...", action: #selector(openScheduleEditor), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Scheduled Statuses...", action: #selector(openStatusSchedule), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "s"))

        menu.addItem(NSMenuItem.separator())

        // Help section
        menu.addItem(NSMenuItem(title: "Show Welcome Guide", action: #selector(openWelcome), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Debug Info", action: #selector(debugMicPermission), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "About Slack Presence", action: #selector(openAbout), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        self.statusItem?.menu = menu

        // Set targets
        for item in menu.items {
            item.target = self
        }
    }

    private func startIconObservation() {
        // withObservationTracking only fires once, so we need to re-register after each change
        // Track ALL stored properties that affect the icon (not just computed ones)
        withObservationTracking {
            _ = appState.currentPresence
            _ = appState.manualOverride
            _ = appState.isInCall
            _ = appState.isDNDActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMenuBarIcon()
                // Re-register observation for next change
                self?.startIconObservation()
            }
        }
    }

    private func updateMenuBarIcon() {
        if let button = statusItem?.button {
            if appState.needsDNDBadge {
                // Create composite icon: sun with zzz badge for Active + DND
                button.image = createCompositeIcon(baseSymbol: "sun.max.fill", badgeSymbol: "zzz")
            } else {
                let iconName = appState.menuBarIcon
                let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Slack Presence")

                if let image = image {
                    let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                    button.image = image.withSymbolConfiguration(config)
                }
            }
        }
    }

    private func createCompositeIcon(baseSymbol: String, badgeSymbol: String) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            // Draw base icon
            let baseConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let base = NSImage(systemSymbolName: baseSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(baseConfig) {
                base.draw(in: CGRect(x: 0, y: 2, width: 14, height: 14))
            }
            // Draw badge in corner
            let badgeConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            if let badge = NSImage(systemSymbolName: badgeSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(badgeConfig) {
                badge.draw(in: CGRect(x: 10, y: 0, width: 8, height: 8))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func forceActive() {
        Task {
            await ScheduleManager.shared.forceActive()
        }
    }

    @objc private func forceAway() {
        Task {
            await ScheduleManager.shared.forceAway()
        }
    }

    @objc private func resumeSchedule() {
        Task {
            await ScheduleManager.shared.resumeSchedule()
        }
    }

    @objc private func setInCall() {
        ScheduleManager.shared.setManualInCall()
    }

    @objc private func clearInCall() {
        ScheduleManager.shared.clearManualInCall()
    }

    @objc private func openScheduleEditor() {
        if scheduleWindow == nil {
            let view = ScheduleEditorView(configState: configState)
            let hostingController = NSHostingController(rootView: view)

            scheduleWindow = NSWindow(contentViewController: hostingController)
            scheduleWindow?.title = "Edit Schedule"
            scheduleWindow?.setContentSize(NSSize(width: 500, height: 450))
            scheduleWindow?.styleMask = [.titled, .closable, .resizable]
            scheduleWindow?.center()
        }

        scheduleWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openStatusSchedule() {
        if statusScheduleWindow == nil {
            let view = StatusScheduleEditorView(configState: configState)
            let hostingController = NSHostingController(rootView: view)

            statusScheduleWindow = NSWindow(contentViewController: hostingController)
            statusScheduleWindow?.title = "Scheduled Statuses"
            statusScheduleWindow?.setContentSize(NSSize(width: 520, height: 450))
            statusScheduleWindow?.styleMask = [.titled, .closable, .resizable]
            statusScheduleWindow?.center()
        }

        statusScheduleWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appState: appState, configState: configState)
            let hostingController = NSHostingController(rootView: view)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 450, height: 520))
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let view = AboutView()
            let hostingController = NSHostingController(rootView: view)

            aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow?.title = "About Slack Presence"
            aboutWindow?.setContentSize(NSSize(width: 280, height: 300))
            aboutWindow?.styleMask = [.titled, .closable]
            aboutWindow?.center()
        }

        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openTokenHelp() {
        if tokenHelpWindow == nil {
            let view = TokenHelpView()
            let hostingController = NSHostingController(rootView: view)

            tokenHelpWindow = NSWindow(contentViewController: hostingController)
            tokenHelpWindow?.title = "Slack Credentials Setup"
            tokenHelpWindow?.setContentSize(NSSize(width: 460, height: 600))
            tokenHelpWindow?.styleMask = [.titled, .closable]
            tokenHelpWindow?.center()
        }

        tokenHelpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleIconUpdateNotification() {
        updateMenuBarIcon()
    }

    @objc private func openWelcome() {
        if welcomeWindow == nil {
            let view = OnboardingView(
                appState: appState,
                configState: configState,
                onComplete: { [weak self] in
                    self?.welcomeWindow?.close()
                }
            )
            let hostingController = NSHostingController(rootView: view)

            welcomeWindow = NSWindow(contentViewController: hostingController)
            welcomeWindow?.title = "Welcome to SlackPresence"
            welcomeWindow?.setContentSize(NSSize(width: 520, height: 650))
            welcomeWindow?.styleMask = [.titled, .closable]
            welcomeWindow?.center()
        }

        welcomeWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func debugMicPermission() {
        if debugWindow == nil {
            let view = DebugView()
            let hostingController = NSHostingController(rootView: view)

            debugWindow = NSWindow(contentViewController: hostingController)
            debugWindow?.title = "Debug Info"
            debugWindow?.setContentSize(NSSize(width: 380, height: 500))
            debugWindow?.styleMask = [.titled, .closable, .resizable]
            debugWindow?.center()
        }

        debugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem?.title = "Status: \(appState.statusText)"
    }
}
