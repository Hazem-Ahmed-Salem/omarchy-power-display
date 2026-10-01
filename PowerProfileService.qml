import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Item {
  id: root

  property string pendingPowerSource: ""

  function applyPowerProfile() {
    pendingPowerSource = UPower.onBattery ? "battery" : "ac"
    if (!powerProfileProcess.running) runPendingPowerProfile()
  }

  function runPendingPowerProfile() {
    if (pendingPowerSource === "") return
    console.log("[PowerProfileService] Applying power profile for: " + pendingPowerSource)
    powerProfileProcess.command = ["omarchy-powerprofiles-set", pendingPowerSource]
    pendingPowerSource = ""
    powerProfileProcess.running = true
  }

  Process {
    id: powerProfileProcess
    onExited: {
      if (root.pendingPowerSource !== "") {
        root.runPendingPowerProfile()
      }
    }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.applyPowerProfile()
    }
  }

  Component.onCompleted: {
    root.applyPowerProfile()
  }
}
