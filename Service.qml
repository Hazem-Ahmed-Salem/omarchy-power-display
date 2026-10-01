import QtQuick
import Quickshell

Item {
  id: root

  property var shell: null

  BatteryAlertService {
    id: batteryAlertService
  }

  PowerProfileService {
    id: powerProfileService
  }

  DisplayRefreshService {
    id: displayRefreshService
  }

  Component.onCompleted: {
    console.log("[hazem.power] Unified service supervisor initialized.")
  }
}
