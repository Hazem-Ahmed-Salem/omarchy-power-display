import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property int batteryThreshold: 10

  readonly property string stateHome: {
    var state = Quickshell.env("XDG_STATE_HOME")
    if (state && state.length) return state
    return (Quickshell.env("HOME") || "") + "/.local/state"
  }
  readonly property string alertPath: stateHome + "/omarchy/battery/alert-percent"

  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-battery"
    property bool notifiedLowBattery: false
  }

  function batteryPercentage() {
    return BatteryModel.batteryPercentage(UPower.displayDevice)
  }

  function isDischarging() {
    return BatteryModel.isDischarging(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging)
  }

  function checkBattery() {
    var state = BatteryModel.shouldWarnLowBattery(
      UPower.displayDevice,
      UPower.onBattery,
      UPowerDeviceState.Discharging,
      batteryThreshold,
      persisted.notifiedLowBattery
    )
    persisted.notifiedLowBattery = state.notifiedLowBattery
    if (state.notify) sendLowBatteryWarning(state.level)
  }

  function sendLowBatteryWarning(level) {
    if (warningProcess.running) return
    console.log("[BatteryAlertService] Triggering low battery warning at " + level + "%")
    warningProcess.command = [
      "omarchy-battery-low",
      String(level)
    ]
    warningProcess.running = true
  }

  function loadAlertThreshold() {
    if (!alertReadProc.running) alertReadProc.running = true
  }

  function updateAlertThreshold(raw) {
    var next = BatteryModel.clampAlertPercent(String(raw || "").trim(), batteryThreshold)
    batteryThreshold = next
  }

  Process { id: warningProcess }

  Process {
    id: alertReadProc
    command: ["bash", "-c", "cat -- " + "'" + root.alertPath.replace(/'/g, "'\\''") + "' 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateAlertThreshold(text)
    }
  }

  FileView {
    id: alertFile
    path: root.alertPath
    watchChanges: true
    printErrors: false
    onFileChanged: root.loadAlertThreshold()
    onLoaded: root.updateAlertThreshold(text())
    onLoadFailed: root.batteryThreshold = 10
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.loadAlertThreshold()
      root.checkBattery()
    }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
    }
  }

  Component.onCompleted: root.loadAlertThreshold()
}
