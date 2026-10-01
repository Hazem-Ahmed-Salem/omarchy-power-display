function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function parsePowerRefresh(raw) {
  var s = String(raw || "")
  var batMark = "===battery==="
  var profMark = "===profiles==="
  var batAt = s.indexOf(batMark)
  if (batAt < 0) {
    return { battery: s, profiles: "" }
  }
  var afterBat = batAt + batMark.length
  var profAt = s.indexOf(profMark, afterBat)
  if (profAt < 0) {
    return { battery: s.substring(afterBat).replace(/^\n/, ""), profiles: "" }
  }
  return {
    battery: s.substring(afterBat, profAt).replace(/^\n/, "").replace(/\n$/, ""),
    profiles: s.substring(profAt + profMark.length).replace(/^\n/, "")
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function profileLabel(name) {
  var raw = String(name || "")
  if (!raw) return ""
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

function parseWatts(raw) {
  var s = String(raw || "").trim().replace(/W$/i, "")
  var n = parseFloat(s)
  return isFinite(n) && n >= 0 ? n : null
}

function batteryHealthPercent(full, design) {
  var f = Number(full)
  var d = Number(design)
  if (!(f > 0) || !(d > 0)) return null
  return Math.max(0, Math.min(100, Math.round((100 * f) / d)))
}

function parseHealthFromSysfs(raw) {
  var lines = String(raw || "").split("\n")
  var full = NaN
  var design = NaN
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    if (parts[0] === "full") full = Number(parts[1])
    if (parts[0] === "design") design = Number(parts[1])
  }
  var pct = batteryHealthPercent(full, design)
  return pct === null ? "" : pct + "%"
}

function healthFromChargeValues(fullText, designText) {
  var pct = batteryHealthPercent(String(fullText || "").trim(), String(designText || "").trim())
  return pct === null ? "" : pct + "%"
}

function parseDurationMinutes(text) {
  var s = String(text || "").trim()
  if (!s || s === "—" || s === "-" || s === "–") return null
  var hours = 0
  var minutes = 0
  var hm = s.match(/(\d+)\s*h/)
  var mm = s.match(/(\d+)\s*m/)
  if (hm) hours = parseInt(hm[1], 10)
  if (mm) minutes = parseInt(mm[1], 10)
  if (!hm && !mm) return null
  if (!isFinite(hours) || !isFinite(minutes)) return null
  return hours * 60 + minutes
}

function formatEtaClock(durationText, nowMs) {
  var mins = parseDurationMinutes(durationText)
  if (mins === null || mins < 0) return ""
  var now = Number(nowMs)
  if (!isFinite(now) || now <= 0) now = Date.now()
  var d = new Date(now + mins * 60000)
  var h = d.getHours()
  var m = d.getMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

function formatTimeWithEta(durationText, idle, nowMs) {
  if (idle) return "-"
  var t = String(durationText || "").trim()
  if (!t) return "—"
  var clock = formatEtaClock(t, nowMs)
  return clock ? (t + " · " + clock) : t
}

function parseTopCpu(raw, limit) {
  var max = Math.max(1, Number(limit) || 5)
  var lines = String(raw || "").split("\n")
  var byName = ({})
  var order = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var cpu = NaN
    var name = ""
    var m = line.match(/^(\d+(?:\.\d+)?)\s+(\S+)\s+(.+)$/)
    if (m) {
      cpu = Number(m[1])
      name = m[3].trim()
    } else {
      m = line.match(/^(\d+(?:\.\d+)?)\s+(.+)$/)
      if (!m) continue
      cpu = Number(m[1])
      name = m[2].trim()
    }
    if (!name || !isFinite(cpu) || cpu < 0) continue

    if (!byName[name]) {
      byName[name] = { name: name, cpu: 0, pids: 0 }
      order.push(name)
    }
    byName[name].cpu += cpu
    byName[name].pids += 1
  }

  var merged = []
  for (var j = 0; j < order.length; j++) merged.push(byName[order[j]])
  merged.sort(function(a, b) { return b.cpu - a.cpu })

  var out = []
  for (var k = 0; k < merged.length && out.length < max; k++) {
    out.push({
      name: merged[k].name,
      cpu: merged[k].cpu,
      pid: "",
      pids: merged[k].pids
    })
  }
  return out
}

function formatCpuPercent(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) v = 0
  if (v >= 10) return Math.round(v) + "%"
  return (Math.round(v * 10) / 10) + "%"
}

function formatCpuPids(pids) {
  var n = Number(pids)
  if (!isFinite(n) || n <= 1) return ""
  return "×" + Math.round(n)
}

// Distinct segment colours for the top-CPU stacked bar. Picked to stay
// readable on dark panels and separable from each other at a glance.
var CPU_BAR_COLORS = ["#5aa8ff", "#ff7a59", "#3dd68c", "#e0c35a", "#c084fc"]

function cpuBarSegments(topCpu, colors) {
  var list = Array.isArray(topCpu) ? topCpu : []
  var palette = Array.isArray(colors) && colors.length > 0 ? colors : CPU_BAR_COLORS
  var total = 0
  var i
  for (i = 0; i < list.length; i++) {
    var cpu = Number(list[i] && list[i].cpu)
    if (isFinite(cpu) && cpu > 0) total += cpu
  }
  if (!(total > 0)) total = 1

  var out = []
  for (i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var value = Number(entry.cpu)
    if (!isFinite(value) || value < 0) value = 0
    var pids = Number(entry.pids)
    if (!isFinite(pids) || pids < 1) pids = 1
    out.push({
      name: String(entry.name || "—"),
      pid: String(entry.pid || ""),
      pids: pids,
      cpu: value,
      share: value / total,
      color: palette[i % palette.length]
    })
  }
  return out
}

function estimateCpuLabelWidth(name, fontPx) {
  var px = Math.max(8, Number(fontPx) || 11)
  return Math.ceil(String(name || "").length * px * 0.66) + 6
}

function cpuLabelOverlaps(a, b, pad) {
  var p = Math.max(0, Number(pad) || 6)
  var a0 = a.labelX - a.textWidth / 2
  var a1 = a.labelX + a.textWidth / 2
  var b0 = b.labelX - b.textWidth / 2
  var b1 = b.labelX + b.textWidth / 2
  return a0 < b1 + p && b0 < a1 + p
}

function clampCpuLabelX(item, barWidth) {
  var half = item.textWidth / 2
  var lx = Number(item.labelX)
  if (!isFinite(lx)) lx = item.centerX
  var W = Math.max(0, Number(barWidth) || 0)
  if (lx - half < 0) lx = half
  if (lx + half > W) lx = Math.max(half, W - half)
  item.labelX = lx
}

// Place on one side while preserving left→right segment order: the label may
// sit at its segment centre or slide right past previous labels on that side,
// but never jump left of them.
function cpuPlaceOrdered(item, placed, barWidth, pad) {
  var half = item.textWidth / 2
  var W = Math.max(0, Number(barWidth) || 0)
  var p = Math.max(0, Number(pad) || 6)
  var minX = half
  var maxX = Math.max(half, W - half)

  if (placed.length > 0) {
    var prev = placed[placed.length - 1]
    minX = Math.max(minX, prev.labelX + prev.textWidth / 2 + p + half)
  }

  if (minX > maxX) return false

  // Prefer the segment centre, but never left of the ordered minimum.
  item.labelX = Math.max(minX, Math.min(maxX, item.centerX))
  return true
}

// Keep side labels in segment order; if the right edge overflows, shift the
// whole lane left then re-enforce order.
function cpuReflowOrdered(placed, barWidth, pad) {
  if (!placed || placed.length === 0) return
  var W = Math.max(0, Number(barWidth) || 0)
  var p = Math.max(0, Number(pad) || 6)
  var i
  var item
  var half
  var minX
  var prev

  for (i = 0; i < placed.length; i++) {
    item = placed[i]
    half = item.textWidth / 2
    minX = half
    if (i > 0) {
      prev = placed[i - 1]
      minX = Math.max(minX, prev.labelX + prev.textWidth / 2 + p + half)
    }
    item.labelX = Math.max(minX, Math.min(Math.max(half, W - half), item.centerX))
  }

  var last = placed[placed.length - 1]
  var overflow = last.labelX + last.textWidth / 2 - W
  if (!(overflow > 0)) return

  for (i = 0; i < placed.length; i++) placed[i].labelX -= overflow
  for (i = 0; i < placed.length; i++) {
    item = placed[i]
    half = item.textWidth / 2
    minX = half
    if (i > 0) {
      prev = placed[i - 1]
      minX = Math.max(minX, prev.labelX + prev.textWidth / 2 + p + half)
    }
    if (item.labelX < minX) item.labelX = minX
  }
}

// layoutAlgorithm: below-first-v4-ordered
// Left → right: fill below while labels clear previous below labels and keep
// segment order. When one does not fit below, park it above (also ordered),
// then resume trying below for the next ones.
// textWidths: optional measured widths (name/%/pids max) per segment index.
function cpuBarLayout(segments, barWidth, gap, textWidths) {
  var list = Array.isArray(segments) ? segments : []
  var n = list.length
  if (n === 0) return []

  var g = Math.max(0, Number(gap) || 0)
  var W = Math.max(0, Number(barWidth) || 0)
  var widths = Array.isArray(textWidths) ? textWidths : []
  var pad = 6
  var inner = Math.max(0, W - g * Math.max(0, n - 1))
  var items = []
  var x = 0
  var i

  for (i = 0; i < n; i++) {
    var seg = list[i] || {}
    var sw = Math.max(2, inner * Math.max(0, Number(seg.share) || 0))
    var measured = Number(widths[i])
    var tw = isFinite(measured) && measured > 0
      ? measured
      : estimateCpuLabelWidth(seg.name, 11)
    var center = x + sw / 2
    var pids = Number(seg.pids)
    if (!isFinite(pids) || pids < 1) pids = 1
    items.push({
      name: String(seg.name || "—"),
      pid: String(seg.pid || ""),
      pids: pids,
      cpu: Number(seg.cpu) || 0,
      share: Number(seg.share) || 0,
      color: seg.color,
      place: "below",
      segmentLeft: x,
      segmentWidth: sw,
      centerX: center,
      textWidth: tw,
      labelX: center
    })
    x += sw + g
  }

  var below = []
  var above = []

  for (i = 0; i < items.length; i++) {
    var item = items[i]
    if (cpuPlaceOrdered(item, below, W, pad)) {
      item.place = "below"
      below.push(item)
      continue
    }
    if (cpuPlaceOrdered(item, above, W, pad)) {
      item.place = "above"
      above.push(item)
      continue
    }
    // No room with order preserved — append above; reflow will pack the lane.
    item.place = "above"
    above.push(item)
  }

  cpuReflowOrdered(below, W, pad)
  cpuReflowOrdered(above, W, pad)

  return items
}

function clampAlertPercent(value, fallback) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = fallback === undefined ? 10 : fallback
  if (n < 5) n = 5
  if (n > 40) n = 40
  return n
}

function parsePreferredProfiles(raw) {
  var kv = parseKeyValue(raw)
  return {
    ac: String(kv.ac || "").trim(),
    battery: String(kv.battery || "").trim()
  }
}

function niceCeil(n) {
  var v = Number(n)
  if (!(v > 0) || !isFinite(v)) return 0
  var exp = Math.pow(10, Math.floor(Math.log(v) / Math.LN10))
  var nice = Math.ceil(v / exp)
  if (nice <= 1) nice = 1
  else if (nice <= 2) nice = 2
  else if (nice <= 5) nice = 5
  else nice = 10
  return nice * exp
}

function pruneWattHistory(points, windowMs, nowMs) {
  var list = Array.isArray(points) ? points.slice() : []
  var window = Math.max(1000, Number(windowMs) || 900000)
  var now = Number(nowMs)
  if (!isFinite(now) || now <= 0) now = Date.now()
  var cutoff = now - window
  while (list.length > 0 && Number(list[0].t) < cutoff) list.shift()
  return list
}

function pushWattSample(history, nowMs, watts, windowMs) {
  var points = Array.isArray(history) ? history.slice() : []
  var now = Number(nowMs)
  if (!isFinite(now) || now <= 0) now = Date.now()
  var w = Number(watts)
  if (!isFinite(w) || w < 0) w = 0

  points.push({ t: now, watts: w })
  return pruneWattHistory(points, windowMs, now)
}

function parseWattHistory(raw, windowMs, nowMs) {
  var text = String(raw || "").trim()
  if (!text) return []
  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return []
  }
  if (!Array.isArray(data)) return []
  var out = []
  for (var i = 0; i < data.length; i++) {
    var p = data[i]
    if (!p) continue
    var t = Number(p.t)
    var w = Number(p.watts)
    if (!isFinite(t) || t <= 0 || !isFinite(w) || w < 0) continue
    out.push({ t: t, watts: w })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return pruneWattHistory(out, windowMs, nowMs)
}

function serializeWattHistory(points) {
  var list = Array.isArray(points) ? points : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    out.push({ t: Number(p.t), watts: Number(p.watts) })
  }
  return JSON.stringify(out) + "\n"
}

function wattExtent(points) {
  var list = Array.isArray(points) ? points : []
  var peak = 0
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p) continue
    var v = Number(p.watts)
    if (isFinite(v) && v > peak) peak = v
  }
  return { peak: peak, axis: peak > 0 ? niceCeil(peak) : 0 }
}

function trafficWindow(points, windowMs, nowMs) {
  var list = Array.isArray(points) ? points : []
  var now = Number(nowMs)
  if (!isFinite(now) || now <= 0) now = Date.now()
  var window = Math.max(1000, Number(windowMs) || 900000)
  var t1 = now
  var t0 = now - window
  if (list.length > 0) {
    var last = list[list.length - 1]
    if (last && Number(last.t) > t1) t1 = Number(last.t)
  }
  return { t0: t0, t1: t1 }
}

function formatWatts(n) {
  var v = Number(n)
  if (!isFinite(v) || v < 0) v = 0
  if (v >= 10) return Math.round(v) + "W"
  var rounded = Math.round(v * 10) / 10
  return String(rounded) + "W"
}


function defaultPowerSaverOpts() {
  return {
    hz60: true,
    brightness: 45,
    wifiPowerSave: true,
    animations: false,
    panelPower: false
  }
}

function clampBrightnessPercent(value, fallback) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = fallback === undefined ? 45 : fallback
  if (n < 1) n = 1
  if (n > 100) n = 100
  return n
}

function parsePowerSaverOpts(raw) {
  var base = defaultPowerSaverOpts()
  var text = String(raw || "").trim()
  if (!text) return base
  var data
  try { data = JSON.parse(text) } catch (e) { return base }
  if (!data || typeof data !== "object") return base
  return {
    hz60: data.hz60 !== false,
    brightness: clampBrightnessPercent(data.brightness, base.brightness),
    wifiPowerSave: data.wifiPowerSave !== false,
    animations: data.animations === true,
    panelPower: data.panelPower === true
  }
}

function serializePowerSaverOpts(opts) {
  var o = opts || defaultPowerSaverOpts()
  return JSON.stringify({
    hz60: !!o.hz60,
    brightness: clampBrightnessPercent(o.brightness, 45),
    wifiPowerSave: !!o.wifiPowerSave,
    animations: !!o.animations,
    panelPower: !!o.panelPower
  }) + "\n"
}

function parsePowerSaverLive(raw) {
  var kv = parseKeyValue(raw)
  return {
    hz: Number(kv.hz) === 60 ? 60 : 120,
    brightness: clampBrightnessPercent(kv.brightness, 50),
    wifiPowerSave: String(kv.wifiPowerSave || "") === "on",
    animations: String(kv.animations || "") !== "off",
    panelPower: String(kv.panelPower || "") === "on"
  }
}

function barTooltip(batteryInfo, timeStatValue) {
  var info = batteryInfo || {}
  var pct = String(info.percentage || "").trim()
  var rate = String(info.rate || "").trim()
  if (!pct && !rate) return ""
  var time = String(timeStatValue || "").trim()
  var parts = []
  if (pct) parts.push(pct)
  if (time && time !== "—" && time !== "-") parts.push(time)
  else if (time === "-") parts.push("-")
  if (rate) parts.push(rate)
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    parsePowerRefresh: parsePowerRefresh,
    profileIcon: profileIcon,
    profileLabel: profileLabel,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    parseWatts: parseWatts,
    batteryHealthPercent: batteryHealthPercent,
    parseHealthFromSysfs: parseHealthFromSysfs,
    healthFromChargeValues: healthFromChargeValues,
    parseDurationMinutes: parseDurationMinutes,
    formatEtaClock: formatEtaClock,
    formatTimeWithEta: formatTimeWithEta,
    parseTopCpu: parseTopCpu,
    formatCpuPercent: formatCpuPercent,
    formatCpuPids: formatCpuPids,
    CPU_BAR_COLORS: CPU_BAR_COLORS,
    cpuBarSegments: cpuBarSegments,
    estimateCpuLabelWidth: estimateCpuLabelWidth,
    cpuBarLayout: cpuBarLayout,
    clampAlertPercent: clampAlertPercent,
    parsePreferredProfiles: parsePreferredProfiles,
    niceCeil: niceCeil,
    pruneWattHistory: pruneWattHistory,
    pushWattSample: pushWattSample,
    parseWattHistory: parseWattHistory,
    serializeWattHistory: serializeWattHistory,
    wattExtent: wattExtent,
    trafficWindow: trafficWindow,
    formatWatts: formatWatts,
    barTooltip: barTooltip,
    defaultPowerSaverOpts: defaultPowerSaverOpts,
    clampBrightnessPercent: clampBrightnessPercent,
    parsePowerSaverOpts: parsePowerSaverOpts,
    serializePowerSaverOpts: serializePowerSaverOpts,
    parsePowerSaverLive: parsePowerSaverLive
  }
}
