import Foundation
import CoreAudio
import AVFoundation

// MARK: - Debug Info Model

struct AudioDeviceInfo: Identifiable {
    let id: AudioDeviceID
    let uid: String  // Unique identifier for persistence
    let name: String
    let isRunning: Bool
    let transportType: String
    let isIgnored: Bool  // Whether device is filtered (virtual, aggregate, user-disabled)
    let ignoreReason: String?  // Why it's ignored (for debugging)
    let isUserDisabled: Bool  // Whether user explicitly disabled this device
}

struct DebugInfo {
    let micPermissionStatus: String
    let inputDevices: [AudioDeviceInfo]
    let anyMicActive: Bool
    let manualOverride: Bool?
    let currentCallState: Bool
    let pendingCallStart: String?
    let pendingCallEnd: String?
    let callStartDelay: Int
    let callEndDelay: Int
    let suppressionRemaining: Int?  // Seconds until auto-detection resumes
}

final class MicMonitor {
    static let shared = MicMonitor()

    private let stateLock = NSLock()
    private var timer: Timer?
    private var isMonitoring = false

    // Callback for state changes
    var onCallStateChanged: ((Bool) -> Void)?

    private var lastKnownState = false

    // Manual override: nil = auto-detect, true/false = manual
    var manualOverride: Bool? = nil

    // Cache input devices (refresh every 10 seconds)
    private var cachedInputDevices: [AudioDeviceID] = []
    private var lastDeviceEnumeration: Date = .distantPast
    private let deviceCacheDuration: TimeInterval = 10.0

    // Debouncing: prevent flickering state changes
    private var potentialCallStartTime: Date?      // When we first detected potential call
    private var potentialCallEndTime: Date?        // When mic first went inactive
    var callStartDelay: TimeInterval = 10.0   // Require Xs of mic activity to confirm call
    var callEndDelay: TimeInterval = 3.0      // Require Xs of mic inactivity to end call

    // Suppression: prevent auto-detection after manual clear
    private var suppressAutoDetectionUntil: Date? = nil
    private let suppressionDuration: TimeInterval = 30.0  // Suppress for 30 seconds after manual clear

    // User-disabled devices (by UID)
    var userDisabledDeviceUIDs: Set<String> = []

    // Transport types that should be ignored (virtual/aggregate devices)
    // Using kAudioDevicePropertyTransportType is more robust than name matching
    private let ignoredTransportTypes: Set<UInt32> = [
        kAudioDeviceTransportTypeVirtual,      // Virtual audio devices (Teams, Zoom, Krisp, etc.)
        kAudioDeviceTransportTypeAggregate,    // User-created aggregate devices
        kAudioDeviceTransportTypeAutoAggregate // System auto-aggregates
    ]

    // Fallback blocklist for edge cases where transport type isn't sufficient
    // (e.g., webcam mics, Bluetooth speakers with mics that report false positives)
    private let fallbackBlocklistPatterns: [String] = [
        // Webcam built-in mics (USB transport but often report active when camera is in use)
        "Logitech BRIO",
        "Logitech C9",  // C920, C922, C930, etc.
        "HD Pro Webcam",
        "Razer Kiyo",
        // Monitor/dock audio that may false-positive
        "LG HDR",
        "DisplayLink",
        // Bluetooth speakers with mics (report active when just playing audio)
        "Logi Z",       // Logitech Z407, Z607, etc. speaker systems
        // Output-only devices that shouldn't be mic sources
        "MacBook Pro Speakers",
        "MacBook Air Speakers",
        "iMac Speakers"
    ]

    private init() {}

    // MARK: - Manual Override

    func setManualInCall() {
        stateLock.lock()
        defer { stateLock.unlock() }

        manualOverride = true
        resetCallState()
        let newState = isInCallLocked()
        if newState != lastKnownState {
            lastKnownState = newState
            onCallStateChanged?(newState)
        }
    }

    /// Force clear call state and suppress auto-detection for a period
    func forceClearCall() {
        stateLock.lock()
        defer { stateLock.unlock() }

        manualOverride = nil
        lastKnownState = false
        resetCallState()
        suppressAutoDetectionUntil = Date().addingTimeInterval(suppressionDuration)
        onCallStateChanged?(false)
    }

    /// Check if auto-detection is currently suppressed
    var isAutoDetectionSuppressed: Bool {
        guard let suppressUntil = suppressAutoDetectionUntil else { return false }
        return Date() < suppressUntil
    }

    /// Remaining suppression seconds (for UI)
    var suppressionRemaining: Int? {
        guard let suppressUntil = suppressAutoDetectionUntil else { return nil }
        let remaining = suppressUntil.timeIntervalSinceNow
        return remaining > 0 ? Int(remaining) : nil
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Check immediately
        checkCallState()

        // Poll every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkCallState()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        onCallStateChanged = nil  // Clear callback to release captured references
    }

    func checkCallState() {
        stateLock.lock()
        defer { stateLock.unlock() }

        let inCall = isInCallLocked()
        if inCall != lastKnownState {
            lastKnownState = inCall
            onCallStateChanged?(inCall)
        }
    }

    // MARK: - Detection Logic

    /// Determines if user is in a call.
    ///
    /// Logic: Manual override takes priority, otherwise mic active = in call
    /// Debouncing: configurable delay to confirm call start/end
    /// Note: Caller must hold stateLock when calling this method
    private func isInCallLocked() -> Bool {
        // Manual override takes priority
        if let override = manualOverride {
            return override
        }

        // Auto-detect from mic
        let micActive = isAnyMicrophoneInUse()
        return applyDebouncing(rawInCall: micActive)
    }

    /// Apply debouncing to prevent flickering state changes
    private func applyDebouncing(rawInCall: Bool) -> Bool {
        let now = Date()

        if rawInCall {
            // Potential call detected
            potentialCallEndTime = nil  // Reset end timer

            if lastKnownState {
                // Already in call, stay in call
                return true
            }

            // Not yet in call - check if we've met the start delay
            if let startTime = potentialCallStartTime {
                if now.timeIntervalSince(startTime) >= callStartDelay {
                    // Met the delay, confirm call started
                    return true
                }
            } else {
                // First detection of potential call
                potentialCallStartTime = now
            }

            // Still waiting for confirmation
            return false

        } else {
            // No call detected (or call ending)
            potentialCallStartTime = nil  // Reset start timer

            if !lastKnownState {
                // Already not in call
                return false
            }

            // Currently in call - check if we should end it
            if let endTime = potentialCallEndTime {
                if now.timeIntervalSince(endTime) >= callEndDelay {
                    // Met the delay, confirm call ended
                    return false
                }
            } else {
                // First detection of mic going inactive
                potentialCallEndTime = now
            }

            // Still waiting for confirmation - stay in call
            return true
        }
    }

    private func resetCallState() {
        potentialCallStartTime = nil
        potentialCallEndTime = nil
    }

    // MARK: - Multi-Device Microphone Detection

    /// Check if ANY connected PHYSICAL input device is in use (filters out virtual devices)
    private func isAnyMicrophoneInUse() -> Bool {
        // If suppression is active, always return false
        if isAutoDetectionSuppressed {
            return false
        }

        let inputDevices = getAllInputDevices()

        for deviceID in inputDevices {
            // Skip virtual/aggregate devices and known false-positive devices
            if shouldIgnoreDevice(deviceID) {
                continue
            }

            if isDeviceRunning(deviceID) {
                return true
            }
        }

        return false
    }

    /// Check if a device should be ignored based on user preference, transport type, or name
    private func shouldIgnoreDevice(_ deviceID: AudioDeviceID) -> Bool {
        // First check: User explicitly disabled this device
        let uid = getDeviceUID(deviceID)
        if userDisabledDeviceUIDs.contains(uid) {
            return true
        }

        // Second check: Use transport type (robust, no maintenance needed)
        let transportType = getDeviceTransportType(deviceID)
        if ignoredTransportTypes.contains(transportType) {
            return true
        }

        // Fallback check: Name-based for edge cases (webcam mics, etc.)
        let name = getDeviceName(deviceID).lowercased()
        for pattern in fallbackBlocklistPatterns {
            if name.contains(pattern.lowercased()) {
                return true
            }
        }

        return false
    }

    /// Get the reason why a device is ignored (for UI display)
    func getIgnoreReason(for deviceID: AudioDeviceID) -> String? {
        let uid = getDeviceUID(deviceID)
        if userDisabledDeviceUIDs.contains(uid) {
            return "User disabled"
        }

        let transportType = getDeviceTransportType(deviceID)
        if ignoredTransportTypes.contains(transportType) {
            return "Transport: \(getTransportTypeName(transportType))"
        }

        let name = getDeviceName(deviceID).lowercased()
        for pattern in fallbackBlocklistPatterns {
            if name.contains(pattern.lowercased()) {
                return "Blocklist: \(pattern)"
            }
        }

        return nil
    }

    /// Get the unique identifier for an audio device
    func getDeviceUID(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &uid
        )

        if status == noErr, let cfUID = uid?.takeRetainedValue() {
            return cfUID as String
        }
        return "unknown-\(deviceID)"
    }

    /// Get the transport type of an audio device
    private func getDeviceTransportType(_ deviceID: AudioDeviceID) -> UInt32 {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &transportType
        )

        guard status == noErr else {
            return kAudioDeviceTransportTypeUnknown
        }

        return transportType
    }

    /// Get human-readable transport type name for debugging
    private func getTransportTypeName(_ transportType: UInt32) -> String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBluetooth: return "Bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth LE"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeAutoAggregate: return "Auto-Aggregate"
        case kAudioDeviceTransportTypePCI: return "PCI"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeAVB: return "AVB"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeContinuityCaptureWired: return "Continuity (Wired)"
        case kAudioDeviceTransportTypeContinuityCaptureWireless: return "Continuity (Wireless)"
        default: return "Unknown (\(transportType))"
        }
    }

    /// Get all audio input devices connected to the system
    private func getAllInputDevices() -> [AudioDeviceID] {
        // Use cached devices if still fresh
        if Date().timeIntervalSince(lastDeviceEnumeration) < deviceCacheDuration {
            return cachedInputDevices
        }

        // Get all audio devices
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr, dataSize > 0 else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        let fetchStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard fetchStatus == noErr else {
            return []
        }

        // Filter for input devices only
        let inputDevices = deviceIDs.filter { deviceID in
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            let status = AudioObjectGetPropertyDataSize(
                deviceID,
                &inputAddress,
                0,
                nil,
                &inputSize
            )

            return status == noErr && inputSize > 0
        }

        // Update cache
        cachedInputDevices = inputDevices
        lastDeviceEnumeration = Date()

        return inputDevices
    }

    /// Check if a specific audio device's INPUT is currently being captured
    private func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        // Method 1: Check if there are active IOProcs for input
        // kAudioDevicePropertyDeviceIsRunningSomewhere with INPUT scope
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeInput,  // Only check input side
            mElement: kAudioObjectPropertyElementMain
        )

        // First check if this property exists for input scope
        if AudioObjectHasProperty(deviceID, &address) {
            var isRunning: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)

            let status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                &isRunning
            )

            if status == noErr {
                return isRunning == 1
            }
        }

        // Fallback: Check global scope but verify device has input capability
        address.mScope = kAudioObjectPropertyScopeGlobal

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isRunning
        )

        if status == noErr && isRunning == 1 {
            // Device is running - but is it running for INPUT?
            // Check if it has active input streams
            return hasActiveInputIOProc(deviceID)
        }

        return false
    }

    /// Check if device has an active IOProc for input capture
    private func hasActiveInputIOProc(_ deviceID: AudioDeviceID) -> Bool {
        // Get the number of IOProcs running on this device
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIOProcStreamUsage,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // If this property isn't supported, fall back to stream check
        guard AudioObjectHasProperty(deviceID, &address) else {
            return checkInputStreamsActive(deviceID)
        }

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else {
            return checkInputStreamsActive(deviceID)
        }

        // If we get here and have data, there's an active IOProc
        return true
    }

    /// Fallback: Check if any input stream is marked active
    private func checkInputStreamsActive(_ deviceID: AudioDeviceID) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &streamsAddress,
            0,
            nil,
            &dataSize
        )

        guard sizeStatus == noErr, dataSize > 0 else {
            return false
        }

        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        guard streamCount > 0 else {
            return false
        }

        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &streamsAddress,
            0,
            nil,
            &dataSize,
            &streamIDs
        )

        guard status == noErr else {
            return false
        }

        for streamID in streamIDs {
            var isActiveAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyIsActive,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var isActive: UInt32 = 0
            var activeSize = UInt32(MemoryLayout<UInt32>.size)

            let activeStatus = AudioObjectGetPropertyData(
                streamID,
                &isActiveAddress,
                0,
                nil,
                &activeSize,
                &isActive
            )

            if activeStatus == noErr && isActive == 1 {
                return true
            }
        }

        return false
    }

    // MARK: - For Testing / Debugging

    func forceCheck() -> (micActive: Bool, inCall: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let mic = isAnyMicrophoneInUse()
        return (mic, isInCallLocked())
    }

    // MARK: - Device Management (for Settings UI)

    /// Get all input devices with their current status (for Settings UI)
    func getAllDevicesInfo() -> [AudioDeviceInfo] {
        let devices = getAllInputDevices()
        return devices.map { deviceID in
            let name = getDeviceName(deviceID)
            let uid = getDeviceUID(deviceID)
            let transportType = getDeviceTransportType(deviceID)
            let transportName = getTransportTypeName(transportType)
            let ignoreReason = getIgnoreReason(for: deviceID)
            let isUserDisabled = userDisabledDeviceUIDs.contains(uid)

            return AudioDeviceInfo(
                id: deviceID,
                uid: uid,
                name: name,
                isRunning: isDeviceRunning(deviceID),
                transportType: transportName,
                isIgnored: ignoreReason != nil,
                ignoreReason: ignoreReason,
                isUserDisabled: isUserDisabled
            )
        }
    }

    /// Enable a device for monitoring (remove from disabled list)
    func enableDevice(uid: String) {
        userDisabledDeviceUIDs.remove(uid)
    }

    /// Disable a device from monitoring (add to disabled list)
    func disableDevice(uid: String) {
        userDisabledDeviceUIDs.insert(uid)
    }

    /// Returns structured debug info for display in UI
    func getDebugInfo() -> DebugInfo {
        let deviceInfos = getAllDevicesInfo()

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let micPermissionText: String
        switch micStatus {
        case .authorized: micPermissionText = "Authorized"
        case .denied: micPermissionText = "Denied"
        case .restricted: micPermissionText = "Restricted"
        case .notDetermined: micPermissionText = "Not Determined"
        @unknown default: micPermissionText = "Unknown"
        }

        var pendingStart: String? = nil
        if let startTime = potentialCallStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            pendingStart = "\(elapsed)s / \(Int(callStartDelay))s"
        }

        var pendingEnd: String? = nil
        if let endTime = potentialCallEndTime {
            let elapsed = Int(Date().timeIntervalSince(endTime))
            pendingEnd = "\(elapsed)s / \(Int(callEndDelay))s"
        }

        return DebugInfo(
            micPermissionStatus: micPermissionText,
            inputDevices: deviceInfos,
            anyMicActive: isAnyMicrophoneInUse(),
            manualOverride: manualOverride,
            currentCallState: lastKnownState,
            pendingCallStart: pendingStart,
            pendingCallEnd: pendingEnd,
            callStartDelay: Int(callStartDelay),
            callEndDelay: Int(callEndDelay),
            suppressionRemaining: suppressionRemaining
        )
    }

    /// Returns all debug info as copyable text
    func getDebugText() -> String {
        let info = getDebugInfo()
        var lines: [String] = []

        lines.append("=== SlackPresence Debug Info ===")
        lines.append("Time: \(Date().formatted())")
        lines.append("")
        lines.append("Mic Permission: \(info.micPermissionStatus)")
        lines.append("")
        lines.append("Input Devices (\(info.inputDevices.count)):")
        for device in info.inputDevices {
            let status = device.isRunning ? "Active" : "Idle"
            let ignoredTag = device.isIgnored ? " [Ignored: \(device.ignoreReason ?? "unknown")]" : ""
            lines.append("  - \(device.name) (\(device.transportType)): \(status)\(ignoredTag)")
        }
        lines.append("")
        lines.append("Call Detection:")
        lines.append("  Any Mic Active: \(info.anyMicActive ? "Yes" : "No")")
        if let manual = info.manualOverride {
            lines.append("  Manual Override: \(manual ? "In Call" : "Not In Call")")
        } else {
            lines.append("  Manual Override: None (auto-detect)")
        }
        lines.append("  Current State: \(info.currentCallState ? "IN CALL" : "Not in call")")
        lines.append("")
        lines.append("Debouncing:")
        lines.append("  Start Delay: \(info.callStartDelay)s")
        lines.append("  End Delay: \(info.callEndDelay)s")
        if let pending = info.pendingCallStart {
            lines.append("  Pending Start: \(pending)")
        }
        if let pending = info.pendingCallEnd {
            lines.append("  Pending End: \(pending)")
        }
        if let suppression = info.suppressionRemaining {
            lines.append("  Suppressed: \(suppression)s remaining")
        }

        return lines.joined(separator: "\n")
    }

    private func getDeviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &name
        )

        if status == noErr, let cfName = name?.takeRetainedValue() {
            return cfName as String
        }
        return "Unknown Device"
    }
}
