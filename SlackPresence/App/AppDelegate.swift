import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
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
    private var troubleshootingWindow: NSWindow?

    // Menu items that need state updates
    private var callDetectionMenuItem: NSMenuItem?
    private var calendarSyncMenuItem: NSMenuItem?
    private var syncCalendarNowMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as menu bar only app (no Dock icon)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openTroubleshooting),
            name: .openTroubleshooting,
            object: nil
        )

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

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        ScheduleManager.shared.stop()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        // Nil out window references when closed to free memory
        if window === scheduleWindow { scheduleWindow = nil }
        else if window === statusScheduleWindow { statusScheduleWindow = nil }
        else if window === settingsWindow { settingsWindow = nil }
        else if window === aboutWindow { aboutWindow = nil }
        else if window === tokenHelpWindow { tokenHelpWindow = nil }
        else if window === debugWindow { debugWindow = nil }
        else if window === welcomeWindow { welcomeWindow = nil }
        else if window === troubleshootingWindow { troubleshootingWindow = nil }

        // Hide from Dock when no windows are open
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private var hasVisibleWindows: Bool {
        [scheduleWindow, statusScheduleWindow, settingsWindow,
         aboutWindow, tokenHelpWindow, debugWindow, welcomeWindow,
         troubleshootingWindow].contains { $0 != nil }
    }

    private func showWindow(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
        let awayItem = NSMenuItem(title: "Set Away", action: #selector(forceAway), keyEquivalent: "W")
        awayItem.keyEquivalentModifierMask = [.command, .shift]  // Cmd+Shift+W (avoid Cmd+W close conflict)
        menu.addItem(awayItem)
        menu.addItem(NSMenuItem(title: "Resume Schedule", action: #selector(resumeSchedule), keyEquivalent: "r"))

        menu.addItem(NSMenuItem.separator())

        // Quick actions - Call Override
        menu.addItem(NSMenuItem(title: "Set In Call", action: #selector(setInCall), keyEquivalent: "i"))  // Cmd+I (avoid Cmd+M minimize conflict)
        let clearInCallItem = NSMenuItem(title: "Clear In Call", action: #selector(clearInCall), keyEquivalent: "I")
        clearInCallItem.keyEquivalentModifierMask = [.command, .shift]  // Cmd+Shift+I
        menu.addItem(clearInCallItem)

        menu.addItem(NSMenuItem.separator())

        // Meeting Override
        menu.addItem(NSMenuItem(title: "Set In Meeting", action: #selector(setInMeeting), keyEquivalent: "m"))
        let clearMeetingItem = NSMenuItem(title: "Clear Meeting", action: #selector(clearMeeting), keyEquivalent: "M")
        clearMeetingItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(clearMeetingItem)

        menu.addItem(NSMenuItem.separator())

        // Windows
        menu.addItem(NSMenuItem(title: "Edit Schedule...", action: #selector(openScheduleEditor), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Scheduled Statuses...", action: #selector(openStatusSchedule), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "s"))

        menu.addItem(NSMenuItem.separator())

        // Feature toggles
        callDetectionMenuItem = NSMenuItem(title: "Call Detection", action: #selector(toggleCallDetection), keyEquivalent: "")
        menu.addItem(callDetectionMenuItem!)

        calendarSyncMenuItem = NSMenuItem(title: "Calendar Sync", action: #selector(toggleCalendarSync), keyEquivalent: "")
        menu.addItem(calendarSyncMenuItem!)

        syncCalendarNowMenuItem = NSMenuItem(title: "Sync Calendar Now", action: #selector(syncCalendarNow), keyEquivalent: "S")
        syncCalendarNowMenuItem!.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(syncCalendarNowMenuItem!)

        menu.addItem(NSMenuItem.separator())

        // Help section
        menu.addItem(NSMenuItem(title: "Show Welcome Guide", action: #selector(openWelcome), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Troubleshooting", action: #selector(openTroubleshooting), keyEquivalent: ""))
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
            _ = appState.isInMeeting
            _ = appState.isOutOfOffice
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

    @objc private func setInMeeting() {
        ScheduleManager.shared.setManualInMeeting()
    }

    @objc private func clearMeeting() {
        ScheduleManager.shared.clearManualMeeting()
    }

    @objc private func toggleCallDetection() {
        let newValue = !configState.callDetectionEnabled
        ScheduleManager.shared.updateCallDetection(enabled: newValue)
        ScheduleManager.shared.saveConfig()
    }

    @objc private func toggleCalendarSync() {
        let newValue = !configState.calendarSyncEnabled
        ScheduleManager.shared.updateCalendarSync(enabled: newValue)
        ScheduleManager.shared.saveConfig()
    }

    @objc private func syncCalendarNow() {
        ScheduleManager.shared.syncCalendarNow()
        appState.updateStatus("Calendar syncing...")
    }

    @objc private func openScheduleEditor() {
        if scheduleWindow == nil {
            let view = ScheduleEditorView(configState: configState)
            let hostingController = NSHostingController(rootView: view)

            scheduleWindow = NSWindow(contentViewController: hostingController)
            scheduleWindow?.title = "Edit Schedule"
            scheduleWindow?.setContentSize(NSSize(width: 500, height: 450))
            scheduleWindow?.styleMask = [.titled, .closable, .resizable]
            scheduleWindow?.delegate = self
            scheduleWindow?.center()
        }

        showWindow(scheduleWindow)
    }

    @objc private func openStatusSchedule() {
        if statusScheduleWindow == nil {
            let view = StatusScheduleEditorView(configState: configState)
            let hostingController = NSHostingController(rootView: view)

            statusScheduleWindow = NSWindow(contentViewController: hostingController)
            statusScheduleWindow?.title = "Scheduled Statuses"
            statusScheduleWindow?.setContentSize(NSSize(width: 520, height: 450))
            statusScheduleWindow?.styleMask = [.titled, .closable, .resizable]
            statusScheduleWindow?.delegate = self
            statusScheduleWindow?.center()
        }

        showWindow(statusScheduleWindow)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(appState: appState, configState: configState)
            let hostingController = NSHostingController(rootView: view)

            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 450, height: 520))
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.delegate = self
            settingsWindow?.center()
        }

        showWindow(settingsWindow)
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let view = AboutView()
            let hostingController = NSHostingController(rootView: view)

            aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow?.title = "About Slack Presence"
            aboutWindow?.setContentSize(NSSize(width: 280, height: 300))
            aboutWindow?.styleMask = [.titled, .closable]
            aboutWindow?.delegate = self
            aboutWindow?.center()
        }

        showWindow(aboutWindow)
    }

    @objc private func openTokenHelp() {
        if tokenHelpWindow == nil {
            let view = TokenHelpView()
            let hostingController = NSHostingController(rootView: view)

            tokenHelpWindow = NSWindow(contentViewController: hostingController)
            tokenHelpWindow?.title = "Slack Credentials Setup"
            tokenHelpWindow?.setContentSize(NSSize(width: 460, height: 600))
            tokenHelpWindow?.styleMask = [.titled, .closable]
            tokenHelpWindow?.delegate = self
            tokenHelpWindow?.center()
        }

        showWindow(tokenHelpWindow)
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
            welcomeWindow?.setContentSize(NSSize(width: 520, height: 780))
            welcomeWindow?.styleMask = [.titled, .closable]
            welcomeWindow?.delegate = self
            welcomeWindow?.center()
        }

        welcomeWindow?.level = .floating
        showWindow(welcomeWindow)
        // Reset to normal after it's visible so it doesn't stay always-on-top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.welcomeWindow?.level = .normal
        }
    }

    @objc private func openTroubleshooting() {
        if troubleshootingWindow == nil {
            let view = TroubleshootingView()
            let hostingController = NSHostingController(rootView: view)

            troubleshootingWindow = NSWindow(contentViewController: hostingController)
            troubleshootingWindow?.title = "Troubleshooting"
            troubleshootingWindow?.setContentSize(NSSize(width: 420, height: 500))
            troubleshootingWindow?.styleMask = [.titled, .closable, .resizable]
            troubleshootingWindow?.delegate = self
            troubleshootingWindow?.center()
        }

        showWindow(troubleshootingWindow)
    }

    @objc private func debugMicPermission() {
        if debugWindow == nil {
            let view = DebugView()
            let hostingController = NSHostingController(rootView: view)

            debugWindow = NSWindow(contentViewController: hostingController)
            debugWindow?.title = "Debug Info"
            debugWindow?.setContentSize(NSSize(width: 380, height: 500))
            debugWindow?.styleMask = [.titled, .closable, .resizable]
            debugWindow?.delegate = self
            debugWindow?.center()
        }

        showWindow(debugWindow)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        statusMenuItem?.title = "Status: \(appState.statusText)"
        callDetectionMenuItem?.state = configState.callDetectionEnabled ? .on : .off
        calendarSyncMenuItem?.state = configState.calendarSyncEnabled ? .on : .off
        syncCalendarNowMenuItem?.isEnabled = configState.calendarSyncEnabled
    }
}
