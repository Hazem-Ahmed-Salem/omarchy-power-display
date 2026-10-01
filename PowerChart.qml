import QtQuick

// Single-series watt history with the same peak-callout model as
// austraz.network/TrafficChart: local maxima only, top N after declutter.
Canvas {
  id: root

  property var points: []
  property real t0: 0
  property real t1: 1
  property real wattsMax: 0
  property string lineColor: "#5aa8ff"
  property string fillColor: "rgba(90, 168, 255, 0.16)"
  property string gridColor: "rgba(255,255,255,0.12)"
  property string fontFamily: "sans-serif"
  property real lineWidth: 1.8
  property int peakCount: 5

  antialiasing: true
  contextType: "2d"

  onPointsChanged: requestPaint()
  onT0Changed: requestPaint()
  onT1Changed: requestPaint()
  onWattsMaxChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onGridColorChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onFillColorChanged: requestPaint()

  function mapX(t, span) {
    return ((Number(t) - t0) / span) * width
  }

  function mapY(value, max) {
    var v = Number(value)
    if (!isFinite(v) || v < 0) v = 0
    var m = Number(max)
    var t = m > 0 ? v / m : 0
    if (t > 1) t = 1
    if (t < 0) t = 0
    return 2 + (1 - t) * (height - 4)
  }

  function formatWatts(n) {
    var v = Number(n)
    if (!isFinite(v) || v < 0) v = 0
    if (v >= 10) return Math.round(v) + "W"
    return (Math.round(v * 10) / 10) + "W"
  }

  function drawGrid(ctx) {
    ctx.strokeStyle = gridColor
    ctx.lineWidth = 1
    var yTop = 2.5
    var yMid = Math.round(height / 2) + 0.5
    var yBot = height - 2.5
    ctx.beginPath()
    ctx.moveTo(0, yTop)
    ctx.lineTo(width, yTop)
    ctx.moveTo(0, yMid)
    ctx.lineTo(width, yMid)
    ctx.moveTo(0, yBot)
    ctx.lineTo(width, yBot)
    ctx.stroke()
  }

  function drawFill(ctx) {
    var list = points
    if (!list || list.length < 2) return
    var span = t1 - t0
    if (!(span > 1) || !(width > 0) || !(height > 0)) return
    var axis = height - 2
    var firstX = null
    var lastX = null

    ctx.beginPath()
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var value = p.watts
      if (typeof value !== "number" || !isFinite(value) || value < 0) continue
      var x = mapX(p.t, span)
      var y = mapY(value, wattsMax)
      if (!isFinite(x) || !isFinite(y)) continue
      if (firstX === null) {
        ctx.moveTo(x, axis)
        ctx.lineTo(x, y)
        firstX = x
      } else {
        ctx.lineTo(x, y)
      }
      lastX = x
    }
    if (firstX === null) return
    ctx.lineTo(lastX, axis)
    ctx.closePath()
    ctx.fillStyle = fillColor
    ctx.fill()
  }

  function drawSeries(ctx) {
    var list = points
    if (!list || list.length < 2) return
    var span = t1 - t0
    if (!(span > 1) || !(width > 0) || !(height > 0)) return

    ctx.beginPath()
    var started = false
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var value = p.watts
      if (typeof value !== "number" || !isFinite(value) || value < 0) {
        started = false
        continue
      }
      var x = mapX(p.t, span)
      var y = mapY(value, wattsMax)
      if (!isFinite(x) || !isFinite(y)) {
        started = false
        continue
      }
      if (!started) {
        ctx.moveTo(x, y)
        started = true
      } else {
        ctx.lineTo(x, y)
      }
    }
    ctx.strokeStyle = lineColor
    ctx.lineWidth = lineWidth
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.stroke()
  }

  function seriesPeaks(list, max) {
    var span = t1 - t0
    if (!list || list.length < 3 || !(span > 1) || !(max > 0)) return []

    var samples = []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var value = p.watts
      if (typeof value !== "number" || !isFinite(value) || value < 0) continue
      var x = mapX(p.t, span)
      var y = mapY(value, max)
      if (!isFinite(x) || !isFinite(y)) continue
      samples.push({ x: x, y: y, value: value })
    }
    if (samples.length < 3) return []

    var floor = height - 6
    var minLift = Math.max(6, (floor - 2) * 0.10)
    var minValue = max * 0.06
    var peaks = []

    function keep(sample, value) {
      if (value < minValue) return
      if (floor - sample.y < minLift) return
      peaks.push({
        px: sample.x,
        py: sample.y,
        value: value,
        text: formatWatts(value),
        color: lineColor
      })
    }

    for (var s = 1; s < samples.length - 1; s++) {
      var cur = samples[s].value
      if (cur > samples[s - 1].value && cur >= samples[s + 1].value) keep(samples[s], cur)
    }

    var last = samples[samples.length - 1]
    if (last.value > samples[samples.length - 2].value) keep(last, last.value)

    return peaks
  }

  readonly property var peaks: computePeaks(points, wattsMax, width, height, t0, t1)

  function computePeaks(pts, max, w, h, a0, a1) {
    if (!(w > 2) || !(h > 2)) return []

    var all = seriesPeaks(pts, max)
    all.sort(function(a, b) { return a.py - b.py })

    var kept = []
    for (var i = 0; i < all.length && kept.length < peakCount; i++) {
      var candidate = all[i]
      var clash = false
      for (var k = 0; k < kept.length; k++) {
        var other = kept[k]
        if (Math.abs(candidate.px - other.px) < 34 && Math.abs(candidate.py - other.py) < 14) {
          clash = true
          break
        }
        if (Math.abs(candidate.value - other.value) <= other.value * 0.12) {
          clash = true
          break
        }
      }
      if (!clash) kept.push(candidate)
    }
    return kept
  }

  onPaint: {
    var ctx = getContext("2d")
    if (!ctx) return
    ctx.reset()
    ctx.clearRect(0, 0, width, height)
    if (width <= 2 || height <= 2) return

    drawGrid(ctx)
    drawFill(ctx)
    drawSeries(ctx)
  }

  Repeater {
    model: root.peaks

    Text {
      id: callout
      required property var modelData

      text: callout.modelData.text
      color: callout.modelData.color
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true

      x: Math.max(0, Math.min(root.width - width, callout.modelData.px - width / 2))
      y: Math.max(0, callout.modelData.py - height - 3)
    }
  }
}
