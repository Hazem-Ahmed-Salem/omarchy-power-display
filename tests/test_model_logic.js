const assert = require("assert")
const Model = require("../Model.js")
const BatteryModel = require("../BatteryModel.js")

console.log("==> Running Model & BatteryModel logic unit tests...")

// Test 1: Alert percent clamp
assert.strictEqual(BatteryModel.clampAlertPercent(4, 10), 5, "Clamps below 5 to 5")
assert.strictEqual(BatteryModel.clampAlertPercent(50, 10), 40, "Clamps above 40 to 40")
assert.strictEqual(BatteryModel.clampAlertPercent("15", 10), 15, "Parses string number")
assert.strictEqual(BatteryModel.clampAlertPercent("invalid", 10), 10, "Uses fallback on invalid input")

// Test 2: Low battery warning logic
const mockDevice = { isPresent: true, percentage: 0.08, state: 2 } // 8%, discharging (state 2)
const warnRes = BatteryModel.shouldWarnLowBattery(mockDevice, true, 2, 10, false)
assert.strictEqual(warnRes.notify, true, "Should notify when <= threshold")
assert.strictEqual(warnRes.notifiedLowBattery, true, "State flag set")

const alreadyWarnedRes = BatteryModel.shouldWarnLowBattery(mockDevice, true, 2, 10, true)
assert.strictEqual(alreadyWarnedRes.notify, false, "Should not notify if already warned")

// Test 3: Watt Extent and Nice Ceil
const wattPoints = [{ t: 1000, watts: 12.4 }, { t: 2000, watts: 28.1 }]
const extent = Model.wattExtent(wattPoints)
assert.strictEqual(extent.peak, 28.1, "Calculates peak correctly")
assert.ok(extent.axis >= 28.1, "Axis ceiling is above peak")

// Test 4: Duration formatting
assert.strictEqual(Model.parseDurationMinutes("2h 30m"), 150)
assert.strictEqual(Model.parseDurationMinutes("45m"), 45)

// Test 5: CPU Bar Segments
const topCpu = [
  { name: "code", cpu: 30, pids: 3 },
  { name: "brave", cpu: 70, pids: 12 }
]
const segments = Model.cpuBarSegments(topCpu)
assert.strictEqual(segments.length, 2)
assert.strictEqual(segments[0].name, "code")
assert.strictEqual(segments[1].name, "brave")
assert.strictEqual(Math.round(segments[0].share * 100), 30)
assert.strictEqual(Math.round(segments[1].share * 100), 70)

console.log("  ✓ All Model & BatteryModel tests passed successfully!")
