import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: root

    property string pluginId: "hazem.power"
    property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

    property bool configLoaded: false
    property bool configValid: false

    // Array of configured monitors: [ { name: string, enabled: bool, acMode: string, batteryMode: string } ]
    property var configuredMonitors: []

    // Reactive power state from Quickshell UPower. No polling.
    property bool onBattery: UPower.onBattery

    // React to monitor hotplug events without polling
    readonly property int screenCount: Quickshell.screens.length
    onScreenCountChanged: {
        console.log("[DisplayRefreshService] Screen count changed to:", screenCount)
        displayController.discoverMonitors()
    }

    // Per-monitor applied state: { [monitorName]: { powerState: string, mode: string } }
    property var appliedState: ({})

    // Queue of pending profile applications: [ { monitorName, mode, powerState } ]
    property var pendingQueue: []
    property bool processingQueue: false

    DisplayController {
        id: displayController

        onDiscoveryCompleted: function(monitors) {
            console.log(
                "[DisplayRefreshService] Service monitor discovery completed (" +
                (Array.isArray(monitors) ? monitors.length : 0) + " monitors discovered)"
            )
            root.loadConfiguration()
            root.tryApplyProfiles()
        }

        onDiscoveryFailed: function(error) {
            console.warn("[DisplayRefreshService] Service monitor discovery failed:", error)
        }

        onModeApplied: function(monitorName, mode) {
            console.log("[DisplayRefreshService] Profile applied successfully:", monitorName, mode)

            if (root.pendingQueue.length > 0 && root.pendingQueue[0].monitorName === monitorName) {
                var item = root.pendingQueue[0]
                var nextState = Object.assign({}, root.appliedState)
                nextState[monitorName] = {
                    powerState: item.powerState,
                    mode: mode
                }
                root.appliedState = nextState
                root.pendingQueue.shift()
            }

            root.processingQueue = false
            root.processNextQueueItem()
        }

        onModeApplyFailed: function(monitorName, mode) {
            console.warn("[DisplayRefreshService] Mode application failed for:", monitorName, mode)

            if (root.pendingQueue.length > 0 && root.pendingQueue[0].monitorName === monitorName) {
                root.pendingQueue.shift()
            }

            root.processingQueue = false
            root.processNextQueueItem()
        }
    }

    FileView {
        id: shellConfig

        path: root.shellConfigPath
        watchChanges: true
        printErrors: true

        onLoaded: {
            root.loadConfiguration()
        }

        onFileChanged: {
            console.log("[DisplayRefreshService] shell.json changed; reloading configuration")
            reload()
        }

        onLoadFailed: function(error) {
            console.warn("[DisplayRefreshService] Failed to load shell.json:", error)
            root.configLoaded = false
            root.configValid = false
        }
    }

    function desiredPowerState() {
        return root.onBattery ? "battery" : "ac"
    }

    function loadConfiguration() {
        var raw = shellConfig.text()

        if (typeof raw !== "string" || raw.trim() === "") {
            console.warn("[DisplayRefreshService] shell.json is empty")
            root.configLoaded = false
            root.configValid = false
            return
        }

        var parsed
        try {
            parsed = JSON.parse(raw)
        } catch (error) {
            console.warn("[DisplayRefreshService] Invalid shell.json:", error)
            root.configLoaded = false
            root.configValid = false
            return
        }

        var entry = root.findPluginBarEntry(parsed)

        if (!entry) {
            console.warn("[DisplayRefreshService] Plugin is not configured in shell.json")
            root.configuredMonitors = []
            root.configLoaded = true
            root.configValid = false
            root.appliedState = ({})
            return
        }

        var rawList = []

        // 1. Check if multi-monitor "monitors" array, JSON string, or object is present
        if (Array.isArray(entry.monitors)) {
            rawList = entry.monitors
        } else if (typeof entry.monitors === "string") {
            try {
                var parsedMonitorsJson = JSON.parse(entry.monitors)
                if (Array.isArray(parsedMonitorsJson)) {
                    rawList = parsedMonitorsJson
                } else if (parsedMonitorsJson && typeof parsedMonitorsJson === "object") {
                    rawList = [parsedMonitorsJson]
                }
            } catch (e) {}
        } else if (entry.monitors && typeof entry.monitors === "object") {
            rawList = [entry.monitors]
        } else if (entry.monitor && typeof entry.monitor === "string") {
            // 2. Migration from legacy single-monitor format
            console.log("[DisplayRefreshService] Migrating legacy single-monitor config for:", entry.monitor)
            rawList = [
                {
                    name: String(entry.monitor).trim(),
                    enabled: true,
                    acMode: String(entry.acMode || "").trim(),
                    batteryMode: String(entry.batteryMode || "").trim()
                }
            ]
        }

        var parsedMonitors = []
        var configNeedsPersist = false

        // Parse and validate existing configured monitors
        for (var i = 0; i < rawList.length; i++) {
            var item = rawList[i]
            if (!item || typeof item !== "object") continue
            var mName = String(item.name || "").trim()
            if (mName === "") continue

            var mEnabled = item.enabled !== false
            var mAcMode = String(item.acMode || "").trim()
            var mBatteryMode = String(item.batteryMode || "").trim()

            // If monitor is connected, ensure modes match active resolution and actually exist
            var liveMon = displayController.findMonitor(mName)
            if (liveMon) {
                if (mAcMode === "" || !displayController.modeMatchesCurrentResolution(liveMon, mAcMode) || !displayController.modeExists(liveMon, mAcMode)) {
                    mAcMode = displayController.highestMode(liveMon)
                    configNeedsPersist = true
                    console.log("[DisplayRefreshService] Falling back to safe default AC mode for", mName + ":", mAcMode)
                }
                if (mBatteryMode === "" || !displayController.modeMatchesCurrentResolution(liveMon, mBatteryMode) || !displayController.modeExists(liveMon, mBatteryMode)) {
                    mBatteryMode = displayController.lowestMode(liveMon)
                    configNeedsPersist = true
                    console.log("[DisplayRefreshService] Falling back to safe default Battery mode for", mName + ":", mBatteryMode)
                }
            }

            parsedMonitors.push({
                name: mName,
                enabled: mEnabled,
                acMode: mAcMode,
                batteryMode: mBatteryMode
            })
        }

        // Auto-detect ANY connected monitors not yet in the configuration
        if (Array.isArray(displayController.monitors) && displayController.monitors.length > 0) {
            for (var d = 0; d < displayController.monitors.length; d++) {
                var discovered = displayController.monitors[d]
                var alreadyKnown = false
                for (var e = 0; e < parsedMonitors.length; e++) {
                    if (parsedMonitors[e].name === discovered.name) {
                        alreadyKnown = true
                        break
                    }
                }

                if (!alreadyKnown) {
                    var defaultAc = displayController.highestMode(discovered)
                    var defaultBattery = displayController.lowestMode(discovered)
                    console.log(
                        "[DisplayRefreshService] Auto-detected display:",
                        discovered.name,
                        "(AC=" + defaultAc + ", Battery=" + defaultBattery + ")"
                    )
                    parsedMonitors.push({
                        name: discovered.name,
                        enabled: true,
                        acMode: defaultAc,
                        batteryMode: defaultBattery
                    })
                    configNeedsPersist = true
                }
            }
        }

        // Detect per-monitor configuration changes and invalidate appliedState for modified monitors
        var nextAppliedState = Object.assign({}, root.appliedState)

        for (var p = 0; p < parsedMonitors.length; p++) {
            var newMon = parsedMonitors[p]
            var oldMon = null
            for (var o = 0; o < root.configuredMonitors.length; o++) {
                if (root.configuredMonitors[o].name === newMon.name) {
                    oldMon = root.configuredMonitors[o]
                    break
                }
            }

            if (!oldMon ||
                oldMon.enabled !== newMon.enabled ||
                oldMon.acMode !== newMon.acMode ||
                oldMon.batteryMode !== newMon.batteryMode) {
                delete nextAppliedState[newMon.name]
                console.log(
                    "[DisplayRefreshService] Profile changed for",
                    newMon.name + "; invalidated applied state for immediate re-application"
                )
            }
        }

        root.appliedState = nextAppliedState
        root.configuredMonitors = parsedMonitors
        root.configLoaded = true
        root.configValid = parsedMonitors.length > 0

        console.log("[DisplayRefreshService] Configuration loaded with", parsedMonitors.length, "monitor(s)")

        if (configNeedsPersist) {
            root.persistSettingsCli(parsedMonitors)
        }

        if (displayController.monitors.length === 0) {
            displayController.discoverMonitors()
        } else {
            root.tryApplyProfiles()
        }
    }

    Process {
        id: cliPersistProcess
    }

    function persistSettingsCli(monitorsList) {
        if (!monitorsList || monitorsList.length === 0 || cliPersistProcess.running) {
            return
        }

        var primary = monitorsList[0]
        var jsonStr = JSON.stringify(monitorsList)

        console.log("[DisplayRefreshService] Persisting auto-detected displays via omarchy bar set")

        cliPersistProcess.command = [
            "sh",
            "-c",
            "omarchy bar set " + root.pluginId + " monitor " + JSON.stringify(primary.name) + " && " +
            "omarchy bar set " + root.pluginId + " acMode " + JSON.stringify(primary.acMode) + " && " +
            "omarchy bar set " + root.pluginId + " batteryMode " + JSON.stringify(primary.batteryMode) + " && " +
            "omarchy bar set " + root.pluginId + " monitors " + JSON.stringify(jsonStr) + " --json"
        ]

        cliPersistProcess.running = true
    }

    function findPluginBarEntry(config) {
        if (!config || typeof config !== "object") {
            return null
        }

        var checkIds = [root.pluginId, "omarchy-power-display", "battery-display-profiles", "omarchy.power", "austraz.power"]

        if (config.bar && config.bar.layout) {
            var sections = ["left", "center", "right"]

            for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
                var section = config.bar.layout[sections[sectionIndex]]
                if (!Array.isArray(section)) continue

                for (var itemIndex = 0; itemIndex < section.length; itemIndex++) {
                    var item = section[itemIndex]
                    if (item && checkIds.indexOf(item.id) !== -1) {
                        return item
                    }
                }
            }
        }

        if (Array.isArray(config.plugins)) {
            for (var pluginIndex = 0; pluginIndex < config.plugins.length; pluginIndex++) {
                var plugin = config.plugins[pluginIndex]
                if (plugin && checkIds.indexOf(plugin.id) !== -1) {
                    return plugin
                }
            }
        }

        return null
    }

    function tryApplyProfiles() {
        if (!root.configLoaded || !root.configValid) {
            return
        }

        var powerState = root.desiredPowerState()

        for (var i = 0; i < root.configuredMonitors.length; i++) {
            var conf = root.configuredMonitors[i]
            var monitorName = conf.name

            if (!conf.enabled) {
                continue
            }

            var monitor = displayController.findMonitor(monitorName)
            if (!monitor) {
                console.log("[DisplayRefreshService] Configured monitor is disconnected (skipped safely):", monitorName)
                continue
            }

            var targetMode = (powerState === "battery" ? conf.batteryMode : conf.acMode)
            if (!targetMode || targetMode === "") {
                console.warn("[DisplayRefreshService] Missing mode for", monitorName, "in power state:", powerState)
                continue
            }

            if (!displayController.validateMode(monitorName, targetMode)) {
                console.warn("[DisplayRefreshService] Refusing unavailable mode for", monitorName + ":", targetMode)
                continue
            }

            var normalizedTarget = displayController.normalizeMode(targetMode)
            var currentMode = displayController.currentMode(monitor)

            // Check if already recorded as applied and currently active on screen
            var lastState = root.appliedState[monitorName]
            if (
                lastState &&
                lastState.powerState === powerState &&
                displayController.modesEquivalent(lastState.mode, normalizedTarget) &&
                displayController.modesEquivalent(currentMode, normalizedTarget)
            ) {
                continue
            }

            // Also check if physical monitor is already at the desired mode
            if (displayController.modesEquivalent(currentMode, normalizedTarget)) {
                console.log(
                    "[DisplayRefreshService] Monitor",
                    monitorName,
                    "is already in desired mode:",
                    normalizedTarget,
                    "(" + powerState + ")"
                )
                var nextState = Object.assign({}, root.appliedState)
                nextState[monitorName] = {
                    powerState: powerState,
                    mode: normalizedTarget
                }
                root.appliedState = nextState
                continue
            }

            // Needs mode change! Check if already in queue
            var alreadyInQueue = false
            for (var q = 0; q < root.pendingQueue.length; q++) {
                if (root.pendingQueue[q].monitorName === monitorName) {
                    alreadyInQueue = true
                    break
                }
            }

            if (!alreadyInQueue) {
                root.pendingQueue.push({
                    monitorName: monitorName,
                    mode: normalizedTarget,
                    powerState: powerState
                })
            }
        }

        root.processNextQueueItem()
    }

    function processNextQueueItem() {
        if (root.processingQueue || root.pendingQueue.length === 0) {
            return
        }

        var item = root.pendingQueue[0]
        root.processingQueue = true

        console.log(
            "[DisplayRefreshService] Applying profile for",
            item.monitorName + ":",
            "powerState =", item.powerState,
            "mode =", item.mode
        )

        var started = displayController.applyMode(item.monitorName, item.mode)
        if (!started) {
            console.warn("[DisplayRefreshService] Failed to initiate mode change for", item.monitorName)
            root.pendingQueue.shift()
            root.processingQueue = false
            root.processNextQueueItem()
        }
    }

    onOnBatteryChanged: {
        console.log(
            "[DisplayRefreshService] Power state changed. onBattery =",
            root.onBattery,
            "(powerState =", root.desiredPowerState(), ")"
        )

        // Clear applied state so all enabled monitors re-evaluate for the new power state
        root.appliedState = ({})
        displayController.discoverMonitors()
    }

    Component.onCompleted: {
        console.log("[DisplayRefreshService] Service started.")
        displayController.discoverMonitors()
    }
}
