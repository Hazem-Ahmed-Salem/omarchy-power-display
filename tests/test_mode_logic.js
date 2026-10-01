// Unit tests for DisplayController resolution preservation and auto-detection logic

const assert = require("assert");

function normalizeMode(mode) {
    if (typeof mode !== "string") return "";
    var result = mode.trim().replace(/Hz$/i, "");
    var parts = result.split("@");
    if (parts.length !== 2) return result;
    var refreshRate = Number(parts[1]);
    if (isNaN(refreshRate)) return result;
    return parts[0] + "@" + refreshRate;
}

function parseMode(mode) {
    var normalized = normalizeMode(mode);
    var parts = normalized.split("@");
    if (parts.length !== 2) return null;
    var resolution = parts[0].split("x");
    if (resolution.length !== 2) return null;
    var width = Number(resolution[0]);
    var height = Number(resolution[1]);
    var refreshRate = Number(parts[1]);
    if (isNaN(width) || isNaN(height) || isNaN(refreshRate)) return null;
    return { width, height, refreshRate };
}

function currentMode(monitor) {
    if (!monitor) return "";
    return normalizeMode(monitor.width + "x" + monitor.height + "@" + monitor.refreshRate);
}

function modesForCurrentResolution(monitor) {
    if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) return [];
    var currentW = Number(monitor.width);
    var currentH = Number(monitor.height);
    if (isNaN(currentW) || isNaN(currentH) || currentW <= 0 || currentH <= 0) return [];

    var matches = [];
    for (var i = 0; i < monitor.availableModes.length; i++) {
        var parsed = parseMode(monitor.availableModes[i]);
        if (!parsed) continue;
        if (parsed.width === currentW && parsed.height === currentH) {
            matches.push({
                raw: monitor.availableModes[i],
                normalized: normalizeMode(monitor.availableModes[i]),
                parsed: parsed
            });
        }
    }

    if (matches.length === 0) {
        for (var j = 0; j < monitor.availableModes.length; j++) {
            var parsedRot = parseMode(monitor.availableModes[j]);
            if (!parsedRot) continue;
            if (parsedRot.width === currentH && parsedRot.height === currentW) {
                matches.push({
                    raw: monitor.availableModes[j],
                    normalized: normalizeMode(monitor.availableModes[j]),
                    parsed: parsedRot
                });
            }
        }
    }

    return matches;
}

function modeMatchesCurrentResolution(monitor, mode) {
    if (!monitor || typeof mode !== "string" || mode.trim() === "") return false;
    var parsed = parseMode(mode);
    if (!parsed) return false;
    var currentW = Number(monitor.width);
    var currentH = Number(monitor.height);
    if (isNaN(currentW) || isNaN(currentH)) return false;
    return (parsed.width === currentW && parsed.height === currentH) ||
           (parsed.width === currentH && parsed.height === currentW);
}

function highestMode(monitor) {
    if (!monitor) return "";
    var matches = modesForCurrentResolution(monitor);
    if (matches.length === 0) return currentMode(monitor);
    var best = matches[0];
    for (var i = 1; i < matches.length; i++) {
        if (matches[i].parsed.refreshRate > best.parsed.refreshRate) {
            best = matches[i];
        }
    }
    return best.normalized;
}

function lowestMode(monitor) {
    if (!monitor) return "";
    var matches = modesForCurrentResolution(monitor);
    if (matches.length === 0) return currentMode(monitor);
    var smoothModes = [];
    for (var i = 0; i < matches.length; i++) {
        if (matches[i].parsed.refreshRate >= 59.0) {
            smoothModes.push(matches[i]);
        }
    }
    var candidates = (smoothModes.length > 0) ? smoothModes : matches;
    var best = candidates[0];
    for (var j = 1; j < candidates.length; j++) {
        if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
            best = candidates[j];
        }
    }
    return best.normalized;
}

// -------------------------------------------------------------
// Tests
// -------------------------------------------------------------

console.log("==> Running DisplayController logic tests...");

// Test 1: Laptop internal display (2560x1600 @ 165Hz / 60Hz)
{
    const mon = {
        name: "eDP-1",
        width: 2560,
        height: 1600,
        refreshRate: 165.002,
        availableModes: ["2560x1600@165.00Hz", "2560x1600@60.00Hz"]
    };
    assert.strictEqual(highestMode(mon), "2560x1600@165", "AC mode must be 2560x1600@165");
    assert.strictEqual(lowestMode(mon), "2560x1600@60", "Battery mode must be 2560x1600@60");
    assert.strictEqual(modeMatchesCurrentResolution(mon, "2560x1600@165"), true);
    assert.strictEqual(modeMatchesCurrentResolution(mon, "1920x1080@60"), false);
    console.log("  ✓ Test 1: Laptop internal display passed");
}

// Test 2: External 4K display running at 1080p
{
    const mon = {
        name: "HDMI-A-1",
        width: 1920,
        height: 1080,
        refreshRate: 144.0,
        availableModes: [
            "3840x2160@144.00Hz",
            "3840x2160@60.00Hz",
            "2560x1440@144.00Hz",
            "1920x1080@144.00Hz",
            "1920x1080@120.00Hz",
            "1920x1080@60.00Hz",
            "640x480@60.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "1920x1080@144", "AC mode must not change to 4K");
    assert.strictEqual(lowestMode(mon), "1920x1080@60", "Battery mode must not change to 640x480");
    console.log("  ✓ Test 2: External multi-resolution display passed (resolution preserved)");
}

// Test 3: Rotated display (portrait 1080x1920)
{
    const mon = {
        name: "DP-2",
        width: 1080,
        height: 1920,
        refreshRate: 144.0,
        availableModes: [
            "1920x1080@144.00Hz",
            "1920x1080@60.00Hz",
            "640x480@60.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "1920x1080@144", "Rotated AC mode must match physical 1080p");
    assert.strictEqual(lowestMode(mon), "1920x1080@60", "Rotated Battery mode must match physical 1080p");
    assert.strictEqual(modeMatchesCurrentResolution(mon, "1920x1080@144"), true);
    console.log("  ✓ Test 3: Rotated display passed");
}

// Test 4: TV / HDMI display with 24Hz/30Hz/60Hz modes
{
    const mon = {
        name: "HDMI-A-2",
        width: 3840,
        height: 2160,
        refreshRate: 60.0,
        availableModes: [
            "3840x2160@60.00Hz",
            "3840x2160@50.00Hz",
            "3840x2160@30.00Hz",
            "3840x2160@24.00Hz"
        ]
    };
    assert.strictEqual(highestMode(mon), "3840x2160@60");
    assert.strictEqual(lowestMode(mon), "3840x2160@60", "Battery mode on TV must pick 60Hz instead of 24Hz slideshow");
    console.log("  ✓ Test 4: TV HDMI display avoided 24/30Hz");
}

// Test 5: Auto-detection multi-monitor reconciliation
{
    const liveMonitors = [
        {
            name: "eDP-1",
            width: 2560,
            height: 1600,
            refreshRate: 165.0,
            availableModes: ["2560x1600@165.00Hz", "2560x1600@60.00Hz"]
        },
        {
            name: "DP-1",
            width: 1920,
            height: 1080,
            refreshRate: 144.0,
            availableModes: ["1920x1080@144.00Hz", "1920x1080@60.00Hz"]
        }
    ];

    // Initial empty config
    const configured = [];

    // Reconcile
    for (const m of liveMonitors) {
        configured.push({
            name: m.name,
            enabled: true,
            acMode: highestMode(m),
            batteryMode: lowestMode(m)
        });
    }

    assert.strictEqual(configured.length, 2);
    assert.strictEqual(configured[0].name, "eDP-1");
    assert.strictEqual(configured[0].acMode, "2560x1600@165");
    assert.strictEqual(configured[0].batteryMode, "2560x1600@60");
    assert.strictEqual(configured[1].name, "DP-1");
    assert.strictEqual(configured[1].acMode, "1920x1080@144");
    assert.strictEqual(configured[1].batteryMode, "1920x1080@60");
    console.log("  ✓ Test 5: Auto-detection multi-monitor reconciliation passed");
}

console.log("==> All tests passed successfully!");
