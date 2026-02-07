# Slack Presence Automation

A macOS menu bar app that automates Slack presence based on your schedule and call status.

## Why?

Slack doesn't have native quiet hours or automatic call detection. This app fills those gaps:

| Gap | Solution |
|-----|----------|
| Calls don't update Slack | When your mic is active (any app), Slack shows :headphones: automatically |
| Slack has no quiet hours | Schedule work hours - automatically go Away outside them |
| DND status isn't visible | Menu bar icon shows when notifications are paused |

## Features

- **Welcome guide** walks you through setup on first launch
- Schedule Active/Away hours per day of the week
- **Scheduled statuses** - set custom Slack status text/emoji at specific times
- Automatic :headphones: status during calls (mic-based detection)
- **Per-device mic selection** - choose which microphones to monitor
- Manual "Set In Call" / "Clear In Call" controls
- Visual DND indicator in menu bar
- Manual presence override when needed
- Launch at Login toggle (built-in, no LaunchAgent needed)
- Runs quietly in the background

## Background

This was one of my first projects using Claude Code - a cool idea I wanted to try while experimenting with AI-assisted development. Built for personal use and research.

By [Tomer Brami](https://github.com/tomerbr1)

---

## Installation

### Prerequisites
- macOS 13.0 or later
- Xcode 15+ (for building from source)

### Build from Source

1. Open the project in Xcode:
   ```bash
   cd slack-presence
   open SlackPresence.xcodeproj
   ```

   Or create a new Xcode project:
   - File → New → Project
   - Choose "App" under macOS
   - Set Product Name to "SlackPresence"
   - Set Interface to "SwiftUI"
   - Drag all files from `SlackPresence/` folder into the project

2. Configure the app:
   - In project settings, set "Application is agent (UIElement)" to YES in Info.plist
   - Or add `LSUIElement = true` to Info.plist

3. Build and run (Cmd+R)

4. The app will appear in your menu bar

### First Launch

On first run, a welcome guide walks you through:

1. **Welcome** - Feature overview
2. **Connect to Slack** - Enter your xoxc token and d cookie (with test connection)
3. **Permissions** - Grant microphone access for call detection
4. **Device Selection** - Choose which microphones to monitor
5. **Schedule** - Review your work hours
6. **Finish** - Enable Launch at Login, start using the app

You can reopen the guide anytime from the menu bar → "Show Welcome Guide".

## Slack Token Setup

Since this is a personal tool without OAuth registration, you need to extract your session token:

### Step 1: Get your xoxc token

1. Open https://app.slack.com in your browser (Chrome/Safari/Firefox)
2. Log into your workspace
3. Open Developer Tools (Cmd+Option+I)
4. Go to **Application** → **Local Storage** → **https://app.slack.com**
5. Find the key `localConfig_v2`
6. Expand: `teams` → `[your-team-id]` → `token`
7. Copy the value starting with `xoxc-...`

### Step 2: Get your d cookie

1. In Developer Tools, go to **Application** → **Cookies** → **https://app.slack.com**
2. Find the cookie named `d`
3. Copy its value (it's a long string)

### Step 3: Enter in the app

1. Click the menu bar icon
2. Go to **Settings...**
3. Paste your xoxc token and d cookie
4. Click **Test Connection** to verify
5. Click **Save Credentials**

### Token Refresh

Your token may expire when you log out of Slack web or after extended periods.
The app will notify you if the token stops working - just repeat the steps above.

## Usage

### Menu Bar

Click the menu bar icon to see:
- Current status (Active/Away/In Call)
- Quick toggles: Set Active (Cmd+A), Set Away (Cmd+W)
- Resume Schedule (Cmd+R) - clears manual override
- Set In Call (Cmd+M) - manually mark yourself as in a call
- Clear In Call (Cmd+Shift+M) - return to auto-detection
- Edit Schedule... (Cmd+,)
- Scheduled Statuses... (Cmd+T)
- Settings... (Cmd+S)
- Show Welcome Guide
- Debug Info (Cmd+D)
- About Slack Presence

### Schedule Editor

- Click on any day to edit its schedule
- Enable/disable specific days
- Set active hours (when you should appear Active)
- Outside active hours, you'll be set to Away
- Use "Copy to Weekdays" or "Copy to All Days" for quick setup

### Call Detection

When enabled (in Settings):
- App monitors all microphone input devices
- When any mic is actively being captured (by any app), your Slack status is set to :headphones:
- When mic usage stops, the status is automatically cleared
- Works with Webex, Zoom, Teams, FaceTime, or any app using your microphone

**Device Selection:**
- In Settings → Devices, toggle which microphones to monitor
- Useful if you have multiple mics and want to ignore some (e.g. virtual devices)

**Manual Override:**
- Use "Set In Call" to manually show :headphones: status (useful when mic detection doesn't trigger)
- Use "Clear In Call" to return to automatic detection

### Scheduled Statuses

Set custom Slack statuses that activate at specific times:
- Open "Scheduled Statuses..." from the menu bar
- Add statuses with emoji, text, and time range
- Statuses activate automatically during their scheduled window
- Enable/disable individual statuses without deleting them

## Configuration

### Config File

Config is stored at `~/.slackpresence/config.json`:

```json
{
  "schedules": {
    "monday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": true },
    "tuesday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": true },
    "wednesday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": true },
    "thursday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": true },
    "friday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": true },
    "saturday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": false },
    "sunday": { "activeStart": "09:00", "activeEnd": "18:00", "enabled": false }
  },
  "callDetectionEnabled": true,
  "callStartDelay": 10,
  "callEndDelay": 3,
  "scheduledStatuses": [],
  "disabledDeviceUIDs": [],
  "hasCompletedOnboarding": false
}
```

### Credentials

Credentials are stored securely in macOS Keychain, not in the config file.

## How It Works

### Presence Management
- Checks current time against your schedule every 60 seconds
- **Syncs with actual Slack status** every 60 seconds (reflects manual changes in Slack)
- Sets Slack to "active" during work hours, "away" outside

### Call Detection
- Monitors all audio input devices (microphones) connected to the system
- When any microphone is actively being captured → sets :headphones: status
- Debouncing prevents flickering:
  - **Call start delay** (default 10s): Mic must be active for this long before triggering
  - **Call end delay** (default 3s): Mic must be inactive for this long before clearing
- Works with any app using your microphone (Webex, Zoom, Teams, FaceTime, etc.)

### Priority
1. Manual call override (if you clicked "Set In Call")
2. Manual presence override (if you clicked "Set Active" or "Set Away")
3. Automatic call detection (mic-based :headphones:)
4. Schedule-based presence

## Troubleshooting

### App doesn't appear in menu bar
- Check System Settings → Login Items to ensure it's enabled
- Make sure the app has `LSUIElement = true` in Info.plist

### Token not working
- Tokens expire - re-extract from Slack web
- Ensure you copied both xoxc token AND d cookie
- Use "Test Connection" button to verify

### Call detection not working
- Grant microphone permissions in System Settings → Privacy & Security → Microphone
- Open Debug window from menu to see mic status and device list
- Check that your microphone shows as "Active" when in a call
- Adjust call start/end delays in Settings if detection is too sensitive or slow
- Use "Set In Call" as a manual fallback if auto-detection doesn't work for your setup

### Schedule not applying
- Check the current day is enabled in Schedule Editor
- Verify the time format is correct (HH:MM)
- Click "Save" after making changes

## Privacy

- All credentials stored in macOS Keychain (encrypted)
- **Microphone access is never recorded** - only checks if the mic is active, never listens to audio
- No data sent to external servers
- Communicates only with Slack's servers using your token
- Config file contains only schedule settings, no credentials

## Project Structure

```
SlackPresence/
├── App/
│   ├── SlackPresenceApp.swift      # Entry point
│   ├── AppDelegate.swift           # Menu bar + window management
│   └── Notifications.swift         # App-wide notification names
├── Views/
│   ├── OnboardingView.swift        # Welcome guide (6-step wizard)
│   ├── ScheduleEditorView.swift    # Per-day schedule UI
│   ├── StatusScheduleEditorView.swift # Scheduled statuses editor
│   ├── SettingsView.swift          # Token config, call detection, devices
│   ├── SharedComponents.swift      # Reusable UI components
│   ├── TokenHelpView.swift         # Credentials setup guide
│   ├── DebugView.swift             # Debug info (mic status, devices)
│   └── AboutView.swift             # About screen
├── Services/
│   ├── SlackClient.swift           # Slack API calls
│   ├── MicMonitor.swift            # Microphone-based call detection
│   ├── ScheduleManager.swift       # Timer logic + call state handling
│   ├── NetworkMonitor.swift        # Network connectivity
│   └── ConfigManager.swift         # Config + Keychain
└── Models/
    ├── Schedule.swift              # Schedule data
    ├── SlackStatus.swift           # Status enums
    └── AppState.swift              # Observable state
```

## License

MIT - Personal use
