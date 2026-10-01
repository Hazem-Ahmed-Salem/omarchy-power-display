import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "hazem.power"
  ipcTarget: "hazem.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false

  property var batteryInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property string acProfile: ""
  property string batteryProfile: ""
  property var topCpu: []
  property var cpuLabelWidths: []
  property string batteryHealth: ""
  property string healthFullRaw: ""
  property string healthDesignRaw: ""
  property string batSysfsDir: ""
  property bool healthUseEnergy: false
  property int profileIndex: 0
  property bool cursorActive: false
  property bool gpuDpmEnabled: false
  property bool gpuDpmKnown: false
  property bool saverHz60: true
  property int saverBrightness: 45
  property bool saverWifiPowerSave: true
  property bool saverAnimations: false
  property bool saverPanelPower: false
  property bool saverOptsReady: false
  property string previousActiveProfile: ""
  property bool applyingSaverOpts: false
  property bool brightnessAdjusting: false
  property int backlightRaw: -1
  property int backlightMax: 0
  property var wattHistory: []
  property bool wattHistoryReady: false
  property bool wattHistoryDirty: false
  readonly property int wattWindowMs: 900000
  readonly property int wattSampleMs: 10000
  readonly property bool showPercentage: setting("showPercentage", true) === true || setting("showPercentage", true) === "true"
  readonly property int lowBatteryAlert: Model.clampAlertPercent(setting("lowBatteryAlert", 10), 10)

  // -------------------------------------------------------------
  // Display & Refresh Rate Properties
  // -------------------------------------------------------------
  property var configuredMonitors: []
  property string activeMonitorName: ""

  readonly property var activeLiveMonitor: {
    var _m = displayController.monitors
    return displayController.findMonitor(activeMonitorName)
  }
  readonly property bool isActiveMonitorConnected: activeLiveMonitor !== null
  readonly property string activeCurrentMode: {
    var _m = displayController.monitors
    return displayController.currentMode(activeLiveMonitor)
  }
  readonly property var activeCurrentParsed: {
    var _m = displayController.monitors
    return displayController.parseMode(activeCurrentMode)
  }
  readonly property var activeResolutionModes: {
    var _m = displayController.monitors
    return displayController.modesForCurrentResolution(activeLiveMonitor)
  }
  readonly property var activeConfiguredMonitor: {
    for (var i = 0; i < configuredMonitors.length; i++) {
      if (configuredMonitors[i].name === activeMonitorName) return configuredMonitors[i]
    }
    return null
  }

  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }
  readonly property string stateHome: {
    var state = Quickshell.env("XDG_STATE_HOME")
    if (state && state.length) return state
    return (Quickshell.env("HOME") || "") + "/.local/state"
  }
  readonly property string shellConfigPath: (Quickshell.env("HOME") || "") + "/.config/omarchy/shell.json"
  readonly property string alertPath: stateHome + "/omarchy/battery/alert-percent"
  readonly property string profileStateDir: stateHome + "/omarchy/powerprofiles"
  readonly property string wattHistoryPath: stateHome + "/omarchy/power/watt-history.json"
  readonly property string powerSaverOptsPath: stateHome + "/omarchy/power/power-saver-opts.json"
  readonly property string powerRefreshBin: Qt.resolvedUrl("bin/power-refresh").toString().replace("file://", "")
  readonly property string powerSaverOptsBin: Qt.resolvedUrl("bin/power-saver-opts").toString().replace("file://", "")
  readonly property bool inPowerSaver: activeProfile === "power-saver"
  readonly property string leafIcon: profileIcon("power-saver")
  readonly property string healthFullPath: batSysfsDir
    ? (batSysfsDir + (healthUseEnergy ? "/energy_full" : "/charge_full"))
    : ""
  readonly property string healthDesignPath: batSysfsDir
    ? (batSysfsDir + (healthUseEnergy ? "/energy_full_design" : "/charge_full_design"))
    : ""
  readonly property var wattScale: Model.wattExtent(wattHistory)
  readonly property var wattWindow: Model.trafficWindow(wattHistory, wattWindowMs, Date.now())
  readonly property var cpuBarSegments: Model.cpuBarSegments(topCpu)
  readonly property real cpuBarGap: Style.space(2)
  readonly property string barTooltipText: Model.barTooltip(batteryInfo, timeStatValue)

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = UPower.displayDevice
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Bar icon blinks theme accent while on battery and at/under the alert slider.
  readonly property bool lowBatteryWarning: root.discharging
    && Math.round(root.batteryFraction * 100) <= root.lowBatteryAlert
  property bool lowBatteryBlinkPhase: false

  readonly property string timeStatValue: {
    if (root.chargeThresholdActive) return root.batteryInfo.threshold || "-"
    return Model.formatTimeWithEta(root.batteryInfo.time, root.batteryFlowIdle, Date.now())
  }

  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function persistSettings(patch) {
    root.settings = Object.assign({}, root.settings, patch)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function refreshBin(mode) {
    if (!batteryPresent || !powerRefreshBin) return
    if (refreshProc.running) return
    refreshProc.command = [powerRefreshBin, mode]
    refreshProc.running = true
  }

  function refresh() {
    refreshBin("--full")
  }

  function sampleBattery() {
    refreshBin("--battery")
  }

  function sampleTopCpu() {
    if (!opened || !batteryPresent) return
    if (!topCpuProc.running) topCpuProc.running = true
  }

  function updateFromRefresh(raw) {
    var parsed = Model.parsePowerRefresh(raw)
    updateKeyValue(parsed.battery)
    if (parsed.profiles) updateProfiles(parsed.profiles)
  }

  function updateKeyValue(raw) {
    var next = Model.parseKeyValue(raw)
    if (Object.keys(next).length === 0) return
    batteryInfo = next
    var watts = Model.parseWatts(next.rate)
    if (watts !== null) {
      wattHistory = Model.pushWattSample(wattHistory, Date.now(), watts, wattWindowMs)
      if (wattHistoryReady) {
        wattHistoryDirty = true
        wattPersistTimer.restart()
      }
    }
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function recomputeHealth() {
    var next = Model.healthFromChargeValues(healthFullRaw, healthDesignRaw)
    if (next) batteryHealth = next
  }

  function updateTopCpu(raw) {
    topCpu = Model.parseTopCpu(raw, 5)
    cpuWidthCollectTimer.restart()
  }

  function collectCpuLabelWidths() {
    var widths = []
    var n = cpuWidthRepeater.count
    for (var i = 0; i < n; i++) {
      var item = cpuWidthRepeater.itemAt(i)
      widths.push(item && item.tw > 0 ? item.tw : 0)
    }
    cpuLabelWidths = widths
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function setPreferredProfile(source, profile) {
    if (!profile || !source) return
    if (source === "ac") acProfile = profile
    else batteryProfile = profile

    var current = root.discharging ? "battery" : "ac"
    if (source === current) {
      if (actionProc.running) return
      actionProc.command = ["omarchy-powerprofiles-set", source, profile]
      actionProc.running = true
      return
    }

    if (source === "ac") acPrefFile.setText(profile + "\n")
    else batteryPrefFile.setText(profile + "\n")
  }

  function togglePercentage() {
    persistSettings({ showPercentage: !root.showPercentage })
  }

  function setLowBatteryAlert(value) {
    var next = Model.clampAlertPercent(value, root.lowBatteryAlert)
    persistSettings({ lowBatteryAlert: next })
    alertFile.setText(String(next) + "\n")
  }

  function refreshGpuDpmState() {
    if (gpuDpmStateProc.running) return
    gpuDpmStateProc.running = true
  }

  function updateGpuDpmState(raw) {
    var lines = String(raw || "").split("\n")
    var inSection = false
    var enabled = false
    var known = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line.indexOf("Name: ") === 0) {
        inSection = line === "Name: amdgpu_dpm"
        continue
      }
      if (!inSection) continue
      if (line.indexOf("Enabled: ") === 0) {
        enabled = line.toLowerCase().indexOf("true") >= 0
        known = true
        break
      }
    }
    gpuDpmEnabled = enabled
    gpuDpmKnown = known
  }

  function setGpuDpmEnabled(enabled) {
    if (gpuDpmActionProc.running) return
    gpuDpmActionProc.command = [
      "powerprofilesctl",
      "configure-action",
      enabled ? "--enable" : "--disable",
      "amdgpu_dpm"
    ]
    gpuDpmActionProc.running = true
  }

  function saverOptsObject() {
    return {
      hz60: saverHz60,
      brightness: saverBrightness,
      wifiPowerSave: saverWifiPowerSave,
      animations: saverAnimations,
      panelPower: saverPanelPower
    }
  }

  function loadPowerSaverOpts(raw) {
    var wasReady = saverOptsReady
    var parsed = Model.parsePowerSaverOpts(raw)
    saverHz60 = parsed.hz60
    saverBrightness = parsed.brightness
    saverWifiPowerSave = parsed.wifiPowerSave
    saverAnimations = parsed.animations
    saverPanelPower = parsed.panelPower
    saverOptsReady = true
    if (!wasReady && activeProfile === "power-saver") applyPowerSaverOptsNow()
  }

  function persistPowerSaverOpts() {
    if (!saverOptsReady) return
    powerSaverOptsFile.setText(Model.serializePowerSaverOpts(saverOptsObject()))
  }

  function refreshPowerSaverLive() {
    if (!powerSaverOptsBin || saverLiveProc.running) return
    saverLiveProc.running = true
  }

  function syncBrightnessFromLive(percent) {
    if (brightnessAdjusting) return
    var next = Model.clampBrightnessPercent(percent, saverBrightness)
    if (next === saverBrightness) return
    saverBrightness = next
    if (inPowerSaver && saverOptsReady) persistPowerSaverOpts()
  }

  function syncBrightnessFromBacklightFiles() {
    if (backlightRaw < 0 || backlightMax <= 0) return
    syncBrightnessFromLive(Math.round((backlightRaw * 100) / backlightMax))
  }

  function updatePowerSaverLive(raw) {
    var live = Model.parsePowerSaverLive(raw)
    if (live.hz === 60) saverHz60 = true
    else if (live.hz === 120 && !inPowerSaver) saverHz60 = false
    if (live.brightness) syncBrightnessFromLive(live.brightness)
  }

  function runSaverOpt(args) {
    if (!powerSaverOptsBin || saverOptProc.running) return
    saverOptProc.command = [powerSaverOptsBin].concat(args)
    saverOptProc.running = true
  }

  function applyPowerSaverOptsNow() {
    if (!powerSaverOptsBin || !saverOptsReady || saverOptProc.running) return
    applyingSaverOpts = true

    // If active monitor has a configured battery mode, apply it safely via DisplayController
    if (activeLiveMonitor && activeConfiguredMonitor && activeConfiguredMonitor.batteryMode) {
      displayController.applyMode(activeConfiguredMonitor.name, activeConfiguredMonitor.batteryMode)
    }

    runSaverOpt([
      "apply-saver",
      saverHz60 ? "1" : "0",
      String(saverBrightness),
      saverWifiPowerSave ? "1" : "0",
      saverAnimations ? "1" : "0",
      saverPanelPower ? "1" : "0"
    ])
  }

  function applyNonPowerSaverOptsNow() {
    if (!powerSaverOptsBin || saverOptProc.running) return
    applyingSaverOpts = true

    // If active monitor has a configured AC mode and we are on AC, restore it safely
    if (!root.discharging && activeLiveMonitor && activeConfiguredMonitor && activeConfiguredMonitor.acMode) {
      displayController.applyMode(activeConfiguredMonitor.name, activeConfiguredMonitor.acMode)
    }

    runSaverOpt(["apply-other"])
  }

  function handleActiveProfileTransition(next) {
    var prev = previousActiveProfile
    previousActiveProfile = next || ""
    if (!next) return
    if (next === "power-saver") {
      if (saverOptsReady) applyPowerSaverOptsNow()
      refreshGpuDpmState()
      refreshPowerSaverLive()
      return
    }
    if (prev === "power-saver") applyNonPowerSaverOptsNow()
    refreshGpuDpmState()
  }

  function setSaverHz60(enabled) {
    saverHz60 = !!enabled
    persistPowerSaverOpts()
    if (activeLiveMonitor) {
      var targetMode = enabled
        ? (activeConfiguredMonitor && activeConfiguredMonitor.batteryMode ? activeConfiguredMonitor.batteryMode : displayController.lowestMode(activeLiveMonitor))
        : (activeConfiguredMonitor && activeConfiguredMonitor.acMode ? activeConfiguredMonitor.acMode : displayController.highestMode(activeLiveMonitor))
      displayController.applyMode(activeLiveMonitor.name, targetMode)
    }
  }

  function setSaverBrightness(value) {
    var next = Model.clampBrightnessPercent(value, saverBrightness)
    saverBrightness = next
    persistPowerSaverOpts()
    if (inPowerSaver) runSaverOpt(["set-brightness", String(next)])
  }

  function setSaverWifiPowerSave(enabled) {
    saverWifiPowerSave = !!enabled
    persistPowerSaverOpts()
    if (inPowerSaver) runSaverOpt(["set-wifi-ps", enabled ? "on" : "off"])
  }

  function setSaverAnimations(enabled) {
    saverAnimations = !!enabled
    persistPowerSaverOpts()
    if (inPowerSaver) runSaverOpt(["set-animations", enabled ? "on" : "off"])
  }

  function setSaverPanelPower(enabled) {
    saverPanelPower = !!enabled
    persistPowerSaverOpts()
    if (inPowerSaver) runSaverOpt(["set-panel-power", enabled ? "on" : "off"])
  }

  // -------------------------------------------------------------
  // Display & Refresh Rate Methods
  // -------------------------------------------------------------
  function loadDisplayConfiguration() {
    var entry = (root.settings && typeof root.settings === "object") ? root.settings : null
    if (!entry || !entry.monitors) {
      var raw = shellConfigFile.text()
      if (raw && typeof raw === "string") {
        try {
          var parsed = JSON.parse(raw)
          var found = findPluginBarEntry(parsed)
          if (found) entry = found
        } catch(e) {}
      }
    }
    if (!entry) return

    var list = []
    if (Array.isArray(entry.monitors)) {
      list = entry.monitors
    } else if (typeof entry.monitors === "string") {
      try {
        var parsedMonitors = JSON.parse(entry.monitors)
        if (Array.isArray(parsedMonitors)) {
          list = parsedMonitors
        } else if (parsedMonitors && typeof parsedMonitors === "object") {
          list = [parsedMonitors]
        }
      } catch(e) {}
    } else if (entry.monitors && typeof entry.monitors === "object") {
      list = [entry.monitors]
    } else if (entry.monitor && typeof entry.monitor === "string") {
      list = [{
        name: String(entry.monitor).trim(),
        enabled: true,
        acMode: String(entry.acMode || "").trim(),
        batteryMode: String(entry.batteryMode || "").trim()
      }]
    }

    var validMonitors = []
    var needsPersist = false

    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!item || typeof item !== "object") continue
      var mName = String(item.name || "").trim()
      if (mName === "") continue

      var mEnabled = item.enabled !== false
      var mAc = String(item.acMode || "").trim()
      var mBat = String(item.batteryMode || "").trim()

      var live = displayController.findMonitor(mName)
      if (live) {
        if (mAc === "" || !displayController.modeMatchesCurrentResolution(live, mAc) || !displayController.modeExists(live, mAc)) {
          mAc = displayController.highestMode(live)
          needsPersist = true
        }
        if (mBat === "" || !displayController.modeMatchesCurrentResolution(live, mBat) || !displayController.modeExists(live, mBat)) {
          mBat = displayController.lowestMode(live)
          needsPersist = true
        }
      }

      validMonitors.push({
        name: mName,
        enabled: mEnabled,
        acMode: mAc,
        batteryMode: mBat
      })
    }

    // Auto-detect any live monitors not yet in list
    if (Array.isArray(displayController.monitors) && displayController.monitors.length > 0) {
      for (var d = 0; d < displayController.monitors.length; d++) {
        var disc = displayController.monitors[d]
        var found = false
        for (var v = 0; v < validMonitors.length; v++) {
          if (validMonitors[v].name === disc.name) { found = true; break }
        }
        if (!found) {
          validMonitors.push({
            name: disc.name,
            enabled: true,
            acMode: displayController.highestMode(disc),
            batteryMode: displayController.lowestMode(disc)
          })
          needsPersist = true
        }
      }
    }

    configuredMonitors = validMonitors
    if (validMonitors.length > 0) {
      var foundCurrent = false
      for (var c = 0; c < validMonitors.length; c++) {
        if (validMonitors[c].name === activeMonitorName) {
          foundCurrent = true
          break
        }
      }
      if (!foundCurrent) {
        var auto = displayController.autoDetectMonitor()
        activeMonitorName = (auto && auto.name) ? auto.name : validMonitors[0].name
      }
    } else {
      activeMonitorName = ""
    }

    if (needsPersist) {
      persistDisplayMonitors(validMonitors)
    }
  }

  function toggleActiveMonitorEnabled() {
    if (!activeConfiguredMonitor) return
    var list = []
    for (var i = 0; i < configuredMonitors.length; i++) {
      var item = Object.assign({}, configuredMonitors[i])
      if (item.name === activeMonitorName) {
        item.enabled = !item.enabled
      }
      list.push(item)
    }
    persistDisplayMonitors(list)
  }

  function findPluginBarEntry(config) {
    if (!config || typeof config !== "object") return null
    var checkIds = [root.moduleName, "hazem.power", "omarchy-power-display", "battery-display-profiles", "omarchy.power", "austraz.power"]

    if (config.bar && config.bar.layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var sec = config.bar.layout[sections[s]]
        if (!Array.isArray(sec)) continue
        for (var i = 0; i < sec.length; i++) {
          if (sec[i] && checkIds.indexOf(sec[i].id) !== -1) return sec[i]
        }
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var p = 0; p < config.plugins.length; p++) {
        if (config.plugins[p] && checkIds.indexOf(config.plugins[p].id) !== -1) return config.plugins[p]
      }
    }
    return null
  }

  function persistDisplayMonitors(updatedList) {
    configuredMonitors = updatedList
    var primary = updatedList.length > 0 ? updatedList[0] : null
    var patch = {
      monitors: updatedList,
      monitor: primary ? primary.name : "",
      acMode: primary ? primary.acMode : "",
      batteryMode: primary ? primary.batteryMode : ""
    }
    persistSettings(patch)

    if (displayCliPersistProc.running) return
    displayCliPersistProc.command = [
      "sh", "-c",
      "omarchy bar set " + root.moduleName + " monitor " + JSON.stringify(primary ? primary.name : "") + " && " +
      "omarchy bar set " + root.moduleName + " acMode " + JSON.stringify(primary ? primary.acMode : "") + " && " +
      "omarchy bar set " + root.moduleName + " batteryMode " + JSON.stringify(primary ? primary.batteryMode : "") + " && " +
      "omarchy bar set " + root.moduleName + " monitors " + JSON.stringify(JSON.stringify(updatedList)) + " --json"
    ]
    displayCliPersistProc.running = true
  }

  function updateMonitorProfileMode(monitorName, profileKey, modeStr) {
    var updated = []
    for (var i = 0; i < configuredMonitors.length; i++) {
      var m = Object.assign({}, configuredMonitors[i])
      if (m.name === monitorName) {
        if (profileKey === "ac") m.acMode = modeStr
        else if (profileKey === "battery") m.batteryMode = modeStr
      }
      updated.push(m)
    }
    persistDisplayMonitors(updated)

    // If changing the active power state profile, immediately apply it
    var currentPowerState = root.discharging ? "battery" : "ac"
    if (profileKey === currentPowerState) {
      displayController.applyMode(monitorName, modeStr)
    }
  }

  function refreshRateOptions(liveMonitor) {
    if (!liveMonitor) {
      if (root.activeConfiguredMonitor) {
        var fallbackOpts = []
        if (root.activeConfiguredMonitor.acMode) {
          var pAc = displayController.parseMode(root.activeConfiguredMonitor.acMode)
          fallbackOpts.push({
            value: displayController.normalizeMode(root.activeConfiguredMonitor.acMode),
            label: pAc ? (Math.round(pAc.refreshRate || pAc.refresh || 0) + " Hz") : root.activeConfiguredMonitor.acMode,
            hz: pAc ? Math.round(pAc.refreshRate || pAc.refresh || 0) : 0
          })
        }
        if (root.activeConfiguredMonitor.batteryMode && !displayController.modesEquivalent(root.activeConfiguredMonitor.batteryMode, root.activeConfiguredMonitor.acMode)) {
          var pBat = displayController.parseMode(root.activeConfiguredMonitor.batteryMode)
          fallbackOpts.push({
            value: displayController.normalizeMode(root.activeConfiguredMonitor.batteryMode),
            label: pBat ? (Math.round(pBat.refreshRate || pBat.refresh || 0) + " Hz") : root.activeConfiguredMonitor.batteryMode,
            hz: pBat ? Math.round(pBat.refreshRate || pBat.refresh || 0) : 0
          })
        }
        return fallbackOpts
      }
      return []
    }

    var curModes = displayController.modesForCurrentResolution(liveMonitor)
    var list = []
    var seen = {}
    for (var i = 0; i < curModes.length; i++) {
      var m = curModes[i]
      var hz = Math.round(m.parsed.refreshRate || m.parsed.refresh || 0)
      var key = String(hz)
      if (seen[key]) continue
      seen[key] = true
      list.push({
        value: m.normalized,
        label: hz + " Hz",
        hz: hz
      })
    }

    // Fallback to all available modes if none matched resolution
    if (list.length === 0 && Array.isArray(liveMonitor.availableModes)) {
      for (var j = 0; j < liveMonitor.availableModes.length; j++) {
        var rawM = liveMonitor.availableModes[j]
        var p = displayController.parseMode(rawM)
        if (p) {
          var rHz = Math.round(p.refreshRate || p.refresh || 0)
          var rKey = String(rHz)
          if (!seen[rKey]) {
            seen[rKey] = true
            list.push({
              value: displayController.normalizeMode(rawM),
              label: rHz + " Hz",
              hz: rHz
            })
          }
        }
      }
    }

    // Sort descending (highest refresh rate first)
    list.sort(function(a, b) {
      return (b.hz || 0) - (a.hz || 0)
    })

    return list
  }

  function currentRefreshValue(liveMonitor, mode) {
    var opts = refreshRateOptions(liveMonitor)
    if (opts.length === 0) return ""
    for (var i = 0; i < opts.length; i++) {
      if (displayController.modesEquivalent(opts[i].value, mode)) {
        return opts[i].value
      }
    }
    return opts[0].value
  }

  function monitorOptions() {
    var list = []
    for (var i = 0; i < root.configuredMonitors.length; i++) {
      var item = root.configuredMonitors[i]
      var isLive = displayController.findMonitor(item.name) !== null
      list.push({
        value: item.name,
        label: (isLive ? "● " : "○ ") + item.name + (item.enabled ? "" : " (disabled)")
      })
    }
    return list
  }

  function ensureStateDirs() {
    if (ensureDirsProc.running) return
    ensureDirsProc.command = [
      "mkdir", "-p",
      stateHome + "/omarchy/battery",
      stateHome + "/omarchy/power",
      profileStateDir
    ]
    ensureDirsProc.running = true
  }

  function loadWattHistory(raw) {
    wattHistory = Model.parseWattHistory(raw, wattWindowMs, Date.now())
    wattHistoryReady = true
  }

  function persistWattHistory() {
    if (!wattHistoryReady || !wattHistoryDirty) return
    wattHistoryDirty = false
    wattHistoryFile.setText(Model.serializeWattHistory(wattHistory))
  }

  IpcHandler {
    target: "hazem.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  DisplayController {
    id: displayController
    onDiscoveryCompleted: function(monitors) {
      root.loadDisplayConfiguration()
    }
  }

  readonly property int screenCount: Quickshell.screens.length
  onScreenCountChanged: {
    displayController.discoverMonitors()
  }

  onSettingsChanged: {
    root.loadDisplayConfiguration()
  }

  Component.onCompleted: {
    ensureStateDirs()
    if (!batDiscoverProc.running) batDiscoverProc.running = true
    if (batteryPresent) refresh()
    refreshGpuDpmState()
    previousActiveProfile = activeProfile
    displayController.discoverMonitors()
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      sampleTopCpu()
      refreshGpuDpmState()
      displayController.discoverMonitors()
      if (inPowerSaver) refreshPowerSaverLive()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: {
    if (!batteryPresent) close()
    else refresh()
  }
  onActiveProfileChanged: root.handleActiveProfileTransition(activeProfile)

  onHealthFullRawChanged: recomputeHealth()
  onHealthDesignRawChanged: recomputeHealth()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: ensureDirsProc
    onExited: {
      if (alertFile.path) alertFile.reload()
      if (wattHistoryFile.path) wattHistoryFile.reload()
      if (powerSaverOptsFile.path) powerSaverOptsFile.reload()
    }
  }

  Process {
    id: batDiscoverProc
    command: ["find", "/sys/class/power_supply", "-maxdepth", "1", "-name", "BAT*"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (line.indexOf("/BAT") >= 0) {
            root.batSysfsDir = line
            break
          }
        }
      }
    }
  }

  Process {
    id: refreshProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateFromRefresh(text) }
  }

  Process {
    id: topCpuProc
    command: ["ps", "-eo", "pcpu=,pid=,comm=", "--sort=-pcpu"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateTopCpu(text) }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: gpuDpmStateProc
    command: ["powerprofilesctl", "list-actions"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateGpuDpmState(text) }
  }

  Process {
    id: gpuDpmActionProc
    onExited: {
      root.refreshGpuDpmState()
      root.refresh()
    }
  }

  Process {
    id: saverLiveProc
    command: [root.powerSaverOptsBin, "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updatePowerSaverLive(text) }
  }

  Process {
    id: saverOptProc
    onExited: {
      root.applyingSaverOpts = false
      if (root.inPowerSaver) root.refreshPowerSaverLive()
      root.refreshGpuDpmState()
    }
  }

  Process {
    id: displayCliPersistProc
  }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadDisplayConfiguration()
  }

  FileView {
    id: acPrefFile
    path: root.profileStateDir + "/ac"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var v = String(text() || "").trim()
      if (v) root.acProfile = v
    }
  }

  FileView {
    id: batteryPrefFile
    path: root.profileStateDir + "/battery"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var v = String(text() || "").trim()
      if (v) root.batteryProfile = v
    }
  }

  FileView {
    id: healthFullFile
    path: root.healthFullPath
    watchChanges: true
    printErrors: false
    onPathChanged: if (path) reload()
    onFileChanged: reload()
    onLoaded: root.healthFullRaw = String(text() || "").trim()
    onLoadFailed: {
      if (!root.healthUseEnergy && root.batSysfsDir) root.healthUseEnergy = true
    }
  }

  FileView {
    id: healthDesignFile
    path: root.healthDesignPath
    watchChanges: true
    printErrors: false
    onPathChanged: if (path) reload()
    onFileChanged: reload()
    onLoaded: root.healthDesignRaw = String(text() || "").trim()
  }

  FileView {
    id: alertFile
    path: root.alertPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = Model.clampAlertPercent(String(text() || "").trim(), root.lowBatteryAlert)
      if (next !== root.lowBatteryAlert) root.persistSettings({ lowBatteryAlert: next })
    }
    onLoadFailed: setText(String(root.lowBatteryAlert) + "\n")
  }

  FileView {
    id: wattHistoryFile
    path: root.wattHistoryPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadWattHistory(text())
    onLoadFailed: {
      root.wattHistoryReady = true
      setText("[]\n")
    }
  }

  FileView {
    id: powerSaverOptsFile
    path: root.powerSaverOptsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadPowerSaverOpts(text())
    onLoadFailed: {
      root.loadPowerSaverOpts("")
      setText(Model.serializePowerSaverOpts(root.saverOptsObject()))
    }
  }

  FileView {
    id: backlightMaxFile
    path: "/sys/class/backlight/amdgpu_bl1/max_brightness"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var n = parseInt(String(text() || "").trim(), 10)
      if (isFinite(n) && n > 0) root.backlightMax = n
      root.syncBrightnessFromBacklightFiles()
    }
  }

  FileView {
    id: backlightRawFile
    path: "/sys/class/backlight/amdgpu_bl1/brightness"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var n = parseInt(String(text() || "").trim(), 10)
      if (isFinite(n) && n >= 0) root.backlightRaw = n
      root.syncBrightnessFromBacklightFiles()
    }
  }

  Timer {
    id: saverLivePollTimer
    interval: 1500
    repeat: true
    running: root.opened && root.inPowerSaver
    onTriggered: root.refreshPowerSaverLive()
  }

  Timer {
    id: wattPersistTimer
    interval: 2000
    repeat: false
    onTriggered: root.persistWattHistory()
  }

  Timer {
    id: cpuWidthCollectTimer
    interval: 16
    repeat: false
    onTriggered: root.collectCpuLabelWidths()
  }

  Timer {
    interval: root.opened ? 5000 : root.wattSampleMs
    running: root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.opened) root.refresh()
      else root.sampleBattery()
    }
  }

  Timer {
    interval: 2500
    running: root.opened && root.batteryPresent
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleTopCpu()
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  Item {
    id: cpuWidthHost
    width: 0
    height: 0
    visible: false

    Repeater {
      id: cpuWidthRepeater
      model: root.cpuBarSegments

      Item {
        required property var modelData
        required property int index
        readonly property real tw: Math.max(nameM.width, pctM.width, pidsM.width)

        TextMetrics {
          id: nameM
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          font.bold: true
          text: modelData.name
        }
        TextMetrics {
          id: pctM
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          text: Model.formatCpuPercent(modelData.cpu)
        }
        TextMetrics {
          id: pidsM
          font.family: root.bar ? root.bar.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption
          text: Model.formatCpuPids(modelData.pids)
        }

        onTwChanged: cpuWidthCollectTimer.restart()
      }
    }
  }

  Timer {
    id: lowBatteryBlinkTimer
    interval: 550
    repeat: true
    running: root.lowBatteryWarning
    onTriggered: root.lowBatteryBlinkPhase = !root.lowBatteryBlinkPhase
    onRunningChanged: if (!running) root.lowBatteryBlinkPhase = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    foreground: root.lowBatteryWarning && root.lowBatteryBlinkPhase
      ? Color.accent
      : (root.bar ? root.bar.barForeground : Color.foreground)
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: root.barTooltipText
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // -------------------------------------------------------------
        // Hero Section
        // -------------------------------------------------------------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              textFormat: Text.PlainText
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // Progress Bar
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // Battery Stats Grid
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
            InfoPair {
              visible: root.batteryHealth !== ""
              label: "Health"
              value: root.batteryHealth
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.timeStatValue
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // -------------------------------------------------------------
        // Power Draw / Charge Rate Graph
        // -------------------------------------------------------------
        Column {
          visible: root.wattHistory.length > 1
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(drawHeader.implicitHeight, drawLegend.implicitHeight)

            PanelSectionHeader {
              id: drawHeader
              text: root.discharging ? "POWER DRAW" : "CHARGE RATE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: drawLegend
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "max " + Model.formatWatts(root.wattScale.peak)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PowerChart {
            width: parent.width
            height: Style.space(72)
            points: root.wattHistory
            t0: root.wattWindow.t0
            t1: root.wattWindow.t1
            wattsMax: root.wattScale.axis
            lineColor: root.bar ? root.bar.foreground.toString() : "#d0d0d0"
            fillColor: root.bar
              ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16).toString()
              : "rgba(208,208,208,0.16)"
            gridColor: root.bar
              ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12).toString()
              : "rgba(255,255,255,0.12)"
            fontFamily: root.bar ? root.bar.fontFamily : "sans-serif"
            peakCount: 5
          }
        }

        // -------------------------------------------------------------
        // Top CPU Monitor
        // -------------------------------------------------------------
        Column {
          visible: root.opened && root.cpuBarSegments.length > 0
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "TOP CPU"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Item {
            id: cpuChart
            width: parent.width
            readonly property var layout: width < 80
              ? []
              : Model.cpuBarLayout(
                  root.cpuBarSegments,
                  width,
                  root.cpuBarGap,
                  root.cpuLabelWidths
                )
            readonly property bool hasAbove: {
              var list = layout
              for (var i = 0; i < list.length; i++) if (list[i].place === "above") return true
              return false
            }
            readonly property bool hasBelow: {
              var list = layout
              for (var i = 0; i < list.length; i++) if (list[i].place === "below") return true
              return false
            }
            readonly property bool anyPids: {
              var list = layout
              for (var i = 0; i < list.length; i++) if (list[i].pids > 1) return true
              return false
            }
            readonly property real laneHeight: Style.font.caption * (anyPids ? 3 : 2) + Style.space(4)
            height: (hasAbove ? laneHeight + Style.space(4) : 0)
              + Style.space(10)
              + (hasBelow ? Style.space(4) + laneHeight : 0)

            Item {
              id: cpuAboveLane
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: cpuChart.hasAbove ? cpuChart.laneHeight : 0
              visible: cpuChart.hasAbove

              Repeater {
                model: cpuChart.layout

                CpuProcessLabel {
                  required property var modelData
                  visible: modelData.place === "above"
                  anchors.bottom: parent.bottom
                  x: Math.max(0, Math.min(parent.width - width, modelData.labelX - width / 2))
                  name: modelData.name
                  cpu: modelData.cpu
                  pids: modelData.pids
                  labelColor: modelData.color
                }
              }
            }

            Row {
              id: cpuBarRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: cpuAboveLane.bottom
              anchors.topMargin: cpuChart.hasAbove ? Style.space(4) : 0
              height: Style.space(10)
              spacing: root.cpuBarGap

              Repeater {
                model: cpuChart.layout

                Rectangle {
                  required property var modelData
                  required property int index
                  readonly property int count: cpuChart.layout.length
                  width: Math.max(
                    Style.space(2),
                    (cpuBarRow.width - root.cpuBarGap * Math.max(0, count - 1)) * modelData.share
                  )
                  height: parent.height
                  radius: Style.space(2)
                  color: modelData.color
                }
              }
            }

            Item {
              id: cpuBelowLane
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: cpuBarRow.bottom
              anchors.topMargin: cpuChart.hasBelow ? Style.space(4) : 0
              height: cpuChart.hasBelow ? cpuChart.laneHeight : 0
              visible: cpuChart.hasBelow

              Repeater {
                model: cpuChart.layout

                CpuProcessLabel {
                  required property var modelData
                  visible: modelData.place === "below"
                  anchors.top: parent.top
                  x: Math.max(0, Math.min(parent.width - width, modelData.labelX - width / 2))
                  name: modelData.name
                  cpu: modelData.cpu
                  pids: modelData.pids
                  labelColor: modelData.color
                }
              }
            }
          }
        }

        // -------------------------------------------------------------
        // Power Profiles Section
        // -------------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: Model.profileLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }

          Column {
            visible: root.profiles.length > 0
            width: parent.width
            spacing: Style.space(8)

            PrefRow {
              title: "ON AC"
              value: root.acProfile || root.activeProfile
              onPicked: function(v) { root.setPreferredProfile("ac", v) }
            }

            PrefRow {
              title: "ON BATTERY"
              value: root.batteryProfile || root.activeProfile
              onPicked: function(v) { root.setPreferredProfile("battery", v) }
            }
          }
        }

        // -------------------------------------------------------------
        // Unified Displays & Refresh Rates Section
        // -------------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(dispHeader.implicitHeight, dispRes.implicitHeight)

            PanelSectionHeader {
              id: dispHeader
              text: "DISPLAYS & REFRESH RATES"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: dispRes
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.activeCurrentParsed
                ? root.activeCurrentParsed.width + "×" + root.activeCurrentParsed.height + " @ " + Math.round(root.activeCurrentParsed.refreshRate || root.activeCurrentParsed.refresh || 0) + " Hz"
                : (root.activeCurrentMode || "—")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          // Monitor Info & Profile Automation Toggle (Matches battery-display-profiles)
          Item {
            width: parent.width
            implicitHeight: Math.max(monInfoRow.implicitHeight, monToggleBtn.implicitHeight)
            visible: root.activeMonitorName !== ""

            Row {
              id: monInfoRow
              spacing: Style.space(8)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: root.activeMonitorName
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              // Connected status badge
              BorderSurface {
                implicitHeight: Style.space(20)
                implicitWidth: badgeRow.implicitWidth + Style.space(12)
                color: root.isActiveMonitorConnected
                  ? Qt.rgba(152/255, 195/255, 121/255, 0.15)
                  : Qt.rgba(224/255, 108/255, 117/255, 0.15)
                radius: Style.cornerRadius

                Row {
                  id: badgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: root.isActiveMonitorConnected ? "●" : "○"
                    color: root.isActiveMonitorConnected ? "#98c379" : "#e06c75"
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: root.isActiveMonitorConnected ? "Connected" : "Disconnected"
                    color: root.isActiveMonitorConnected ? "#98c379" : "#e06c75"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            Button {
              id: monToggleBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              fontSize: Style.font.caption
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              bordered: true
              active: root.activeConfiguredMonitor ? root.activeConfiguredMonitor.enabled : false
              text: (root.activeConfiguredMonitor && root.activeConfiguredMonitor.enabled) ? "󰄬 Enabled" : "󰅖 Disabled"
              onClicked: root.toggleActiveMonitorEnabled()
            }
          }

          // Monitor Selection Chips (when more than 1 monitor exists)
          Row {
            visible: root.configuredMonitors.length > 1
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.configuredMonitors

              Button {
                required property var modelData
                readonly property bool isLive: displayController.findMonitor(modelData.name) !== null
                text: (isLive ? "● " : "○ ") + modelData.name
                fontSize: Style.font.caption
                foreground: isLive ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.activeMonitorName === modelData.name
                onClicked: root.activeMonitorName = modelData.name
              }
            }
          }

          // Disconnected notice if inactive
          Text {
            visible: !root.isActiveMonitorConnected && root.activeMonitorName !== ""
            width: parent.width
            text: "Monitor is currently disconnected. Profile settings will automatically apply when connected."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // Manual Refresh Rate Dropdown for the active display
          Column {
            visible: root.isActiveMonitorConnected && root.refreshRateOptions(root.activeLiveMonitor).length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "MANUAL REFRESH RATE (" + (root.activeMonitorName || "Display") + ")"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Dropdown {
              id: manualRefreshRateDropdown
              width: parent.width
              showLabel: false
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              value: root.currentRefreshValue(root.activeLiveMonitor, root.activeCurrentMode)
              options: root.refreshRateOptions(root.activeLiveMonitor)
              onChanged: function(val) {
                displayController.applyMode(root.activeMonitorName, val)
              }
            }

            // Quick Toggle Pills for instant 1-click access
            Row {
              id: hzButtonsRow
              width: parent.width
              spacing: Style.space(6)
              visible: root.refreshRateOptions(root.activeLiveMonitor).length <= 4

              readonly property real cellWidth: root.activeResolutionModes.length > 0
                ? (width - spacing * (root.activeResolutionModes.length - 1)) / root.activeResolutionModes.length
                : 0

              Repeater {
                model: root.activeResolutionModes

                Button {
                  required property var modelData
                  width: hzButtonsRow.cellWidth
                  text: Math.round(modelData.parsed.refreshRate || modelData.parsed.refresh || 0) + " Hz"
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: displayController.modesEquivalent(root.activeCurrentMode, modelData.raw)
                  onClicked: {
                    displayController.applyMode(root.activeMonitorName, modelData.raw)
                  }
                }
              }
            }
          }

          // AC & Battery Automated Profiles Dropdowns
          Row {
            visible: root.refreshRateOptions(root.activeLiveMonitor).length > 0
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(5)

              PanelSectionHeader {
                text: "DISPLAY ON AC"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Dropdown {
                id: acProfileDropdown
                width: parent.width
                showLabel: false
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                value: root.currentRefreshValue(root.activeLiveMonitor, root.activeConfiguredMonitor ? root.activeConfiguredMonitor.acMode : "")
                options: root.refreshRateOptions(root.activeLiveMonitor)
                onChanged: function(val) {
                  root.updateMonitorProfileMode(root.activeMonitorName, "ac", val)
                }
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(5)

              PanelSectionHeader {
                text: "DISPLAY ON BATTERY"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Dropdown {
                id: batProfileDropdown
                width: parent.width
                showLabel: false
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                value: root.currentRefreshValue(root.activeLiveMonitor, root.activeConfiguredMonitor ? root.activeConfiguredMonitor.batteryMode : "")
                options: root.refreshRateOptions(root.activeLiveMonitor)
                onChanged: function(val) {
                  root.updateMonitorProfileMode(root.activeMonitorName, "battery", val)
                }
              }
            }
          }
        }

        // -------------------------------------------------------------
        // Power Saver Options Section
        // -------------------------------------------------------------
        Column {
          visible: root.inPowerSaver
          width: parent.width
          spacing: Style.space(10)

          PanelSeparator {
            foreground: root.bar.foreground
          }

          PanelSectionHeader {
            text: "POWER SAVER OPTIONS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(brightHeader.implicitHeight, brightValue.implicitHeight)

              Row {
                id: brightHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  text: root.leafIcon
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                PanelSectionHeader {
                  text: "BRIGHTNESS"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }
              }

              Text {
                id: brightValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.saverBrightness + "%"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            PanelSlider {
              bar: root.bar
              width: parent.width
              minimum: 1
              maximum: 100
              step: 1
              integer: true
              value: root.saverBrightness
              onMoved: function(v) {
                root.brightnessAdjusting = true
                root.saverBrightness = Model.clampBrightnessPercent(v, root.saverBrightness)
              }
              onReleased: function(v) {
                root.brightnessAdjusting = false
                root.setSaverBrightness(v)
              }
            }
          }

          // Wi-Fi Power Save
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "WIFI POWER SAVE"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Off"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: !root.saverWifiPowerSave
                enabled: !saverOptProc.running
                onClicked: root.setSaverWifiPowerSave(false)
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                iconText: root.leafIcon
                text: "On"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.saverWifiPowerSave
                enabled: !saverOptProc.running
                onClicked: root.setSaverWifiPowerSave(true)
              }
            }
          }

          // Hyprland Animations
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "ANIMATIONS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                iconText: root.leafIcon
                text: "Off"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: !root.saverAnimations
                enabled: !saverOptProc.running
                onClicked: root.setSaverAnimations(false)
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "On"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.saverAnimations
                enabled: !saverOptProc.running
                onClicked: root.setSaverAnimations(true)
              }
            }
          }

          // GPU DPM
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "GPU DPM"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Disable"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.gpuDpmKnown && !root.gpuDpmEnabled
                enabled: !gpuDpmActionProc.running
                onClicked: root.setGpuDpmEnabled(false)
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                iconText: root.leafIcon
                text: "Enable"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.gpuDpmKnown && root.gpuDpmEnabled
                enabled: !gpuDpmActionProc.running
                onClicked: root.setGpuDpmEnabled(true)
              }
            }
          }

          // Panel Power
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "PANEL POWER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Disable"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: !root.saverPanelPower
                enabled: !saverOptProc.running
                onClicked: root.setSaverPanelPower(false)
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                iconText: root.leafIcon
                text: "Enable"
                fontSize: Style.font.caption
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.saverPanelPower
                enabled: !saverOptProc.running
                onClicked: root.setSaverPanelPower(true)
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // -------------------------------------------------------------
        // Low Battery Alert Slider
        // -------------------------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(alertHeader.implicitHeight, alertValue.implicitHeight)

            PanelSectionHeader {
              id: alertHeader
              text: "LOW BATTERY ALERT"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: alertValue
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.lowBatteryAlert + "%"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          PanelSlider {
            bar: root.bar
            width: parent.width
            minimum: 5
            maximum: 40
            step: 1
            integer: true
            value: root.lowBatteryAlert
            onMoved: function(v) {
              root.settings = Object.assign({}, root.settings, {
                lowBatteryAlert: Model.clampAlertPercent(v, root.lowBatteryAlert)
              })
            }
            onReleased: function(v) { root.setLowBatteryAlert(v) }
          }
        }
      }
    }
  }

  // -------------------------------------------------------------
  // Inline Components
  // -------------------------------------------------------------
  component CpuProcessLabel: Column {
    property string name: ""
    property real cpu: 0
    property int pids: 1
    property color labelColor: root.bar.foreground

    spacing: Style.space(1)
    width: Math.max(nameText.implicitWidth, pctText.implicitWidth, pidsText.visible ? pidsText.implicitWidth : 0)

    Text {
      id: nameText
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: name
      color: labelColor
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      id: pctText
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: Model.formatCpuPercent(cpu)
      color: root.bar.foreground
      opacity: 0.55
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      id: pidsText
      anchors.horizontalCenter: parent.horizontalCenter
      visible: pids > 1
      textFormat: Text.PlainText
      text: Model.formatCpuPids(pids)
      color: root.bar.foreground
      opacity: 0.4
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component PrefRow: Column {
    id: pref
    property string title: ""
    property string value: ""
    signal picked(string value)

    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader {
      text: pref.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Row {
      id: prefButtons
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: root.profiles.length > 0
        ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
        : 0

      Repeater {
        model: root.profiles
        Button {
          required property var modelData
          width: prefButtons.cellWidth
          text: Model.profileLabel(String(modelData))
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          active: pref.value === modelData
          onClicked: pref.picked(String(modelData))
        }
      }
    }
  }


  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel {
      text: label
      elide: Text.ElideRight
      width: Math.min(implicitWidth, parent.width * 0.62)
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].width - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
