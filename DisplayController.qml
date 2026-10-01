import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var monitors: []

    readonly property bool busy:
        commandProcess.running

    property string operation: ""

    property string pendingMonitorName: ""
    property string pendingMode: ""

    property var pendingDiscoveryMonitors: null
    property string pendingDiscoveryError: ""

    signal discoveryCompleted(var monitors)
    signal discoveryFailed(string error)

    signal modeApplied(
        string monitorName,
        string mode
    )

    signal modeApplyFailed(
        string monitorName,
        string mode
    )

    /*
     * ---------------------------------------------------------
     * Monitor discovery
     * ---------------------------------------------------------
     */

    function discoverMonitors() {
        if (commandProcess.running) {
            console.log(
                "[Battery Display Profiles] Discovery requested while another operation is running"
            )

            return false
        }

        operation = "discover"

        pendingDiscoveryMonitors = null
        pendingDiscoveryError = ""

        commandProcess.command = [
            "hyprctl",
            "monitors",
            "-j"
        ]

        console.log(
            "[Battery Display Profiles] Discovering monitors..."
        )

        commandProcess.running = true

        return true
    }

    /*
     * ---------------------------------------------------------
     * Monitor lookup
     * ---------------------------------------------------------
     */

    function findMonitor(name) {
        for (
            var i = 0;
            i < monitors.length;
            i++
        ) {
            if (
                monitors[i].name === name
            ) {
                return monitors[i]
            }
        }

        return null
    }

    function autoDetectMonitor() {
        if (!Array.isArray(monitors) || monitors.length === 0) {
            return null
        }

        // 1. Prefer internal laptop display (eDP, LVDS)
        for (var i = 0; i < monitors.length; i++) {
            if (/^(eDP|LVDS)/i.test(monitors[i].name)) {
                return monitors[i]
            }
        }

        // 2. Prefer focused monitor
        for (var j = 0; j < monitors.length; j++) {
            if (monitors[j].focused === true) {
                return monitors[j]
            }
        }

        // 3. Fallback to first discovered monitor
        return monitors[0]
    }

    /*
     * ---------------------------------------------------------
     * Current resolution modes lookup
     *
     * Finds all modes matching the monitor's active resolution,
     * accounting for normal and rotated displays (90/270 deg).
     * ---------------------------------------------------------
     */

    function modesForCurrentResolution(monitor) {
        if (!monitor || !Array.isArray(monitor.availableModes) || monitor.availableModes.length === 0) {
            return []
        }

        var currentW = Number(monitor.width)
        var currentH = Number(monitor.height)
        if (isNaN(currentW) || isNaN(currentH) || currentW <= 0 || currentH <= 0) {
            return []
        }

        var matches = []

        // 1. Direct match with current width and height
        for (var i = 0; i < monitor.availableModes.length; i++) {
            var parsed = parseMode(monitor.availableModes[i])
            if (!parsed) continue

            if (parsed.width === currentW && parsed.height === currentH) {
                matches.push({
                    raw: monitor.availableModes[i],
                    normalized: normalizeMode(monitor.availableModes[i]),
                    parsed: parsed
                })
            }
        }

        // 2. Swapped match for rotated displays (transform 90/270 degrees)
        if (matches.length === 0) {
            for (var j = 0; j < monitor.availableModes.length; j++) {
                var parsedRot = parseMode(monitor.availableModes[j])
                if (!parsedRot) continue

                if (parsedRot.width === currentH && parsedRot.height === currentW) {
                    matches.push({
                        raw: monitor.availableModes[j],
                        normalized: normalizeMode(monitor.availableModes[j]),
                        parsed: parsedRot
                    })
                }
            }
        }

        matches.sort(function(a, b) {
            return a.parsed.refreshRate - b.parsed.refreshRate
        })

        return matches
    }

    function modeMatchesCurrentResolution(monitor, mode) {
        if (!monitor || typeof mode !== "string" || mode.trim() === "") {
            return false
        }

        var parsed = parseMode(mode)
        if (!parsed) {
            return false
        }

        var currentW = Number(monitor.width)
        var currentH = Number(monitor.height)
        if (isNaN(currentW) || isNaN(currentH)) {
            return false
        }

        return (parsed.width === currentW && parsed.height === currentH) ||
               (parsed.width === currentH && parsed.height === currentW)
    }

    function highestMode(monitor) {
        if (!monitor) {
            return ""
        }

        var matches = modesForCurrentResolution(monitor)
        if (matches.length === 0) {
            // Guarantee: NEVER change resolution, fallback to currentMode
            return currentMode(monitor)
        }

        var best = matches[0]
        for (var i = 1; i < matches.length; i++) {
            if (matches[i].parsed.refreshRate > best.parsed.refreshRate) {
                best = matches[i]
            }
        }

        return best.normalized
    }

    function lowestMode(monitor) {
        if (!monitor) {
            return ""
        }

        var matches = modesForCurrentResolution(monitor)
        if (matches.length === 0) {
            // Guarantee: NEVER change resolution, fallback to currentMode
            return currentMode(monitor)
        }

        // For battery mode, prefer ~60Hz if available (>= 59.0Hz)
        // to avoid picking an unusable 24Hz/30Hz mode on HDMI/TV displays.
        var smoothModes = []
        for (var i = 0; i < matches.length; i++) {
            if (matches[i].parsed.refreshRate >= 59.0) {
                smoothModes.push(matches[i])
            }
        }

        var candidates = (smoothModes.length > 0) ? smoothModes : matches
        var best = candidates[0]
        for (var j = 1; j < candidates.length; j++) {
            if (candidates[j].parsed.refreshRate < best.parsed.refreshRate) {
                best = candidates[j]
            }
        }

        return best.normalized
    }

    /*
     * ---------------------------------------------------------
     * Mode normalization
     * ---------------------------------------------------------
     */

    function normalizeMode(mode) {
        if (
            typeof mode !== "string"
        ) {
            return ""
        }

        var result =
            mode.trim()

        result =
            result.replace(
                /Hz$/i,
                ""
            )

        var parts =
            result.split("@")

        if (
            parts.length !== 2
        ) {
            return result
        }

        var refreshRate =
            Number(parts[1])

        if (
            isNaN(refreshRate)
        ) {
            return result
        }

        return (
            parts[0] +
            "@" +
            refreshRate
        )
    }

    function parseMode(mode) {
        var normalized =
            normalizeMode(mode)

        var parts =
            normalized.split("@")

        if (
            parts.length !== 2
        ) {
            return null
        }

        var resolution =
            parts[0].split("x")

        if (
            resolution.length !== 2
        ) {
            return null
        }

        var width =
            Number(resolution[0])

        var height =
            Number(resolution[1])

        var refreshRate =
            Number(parts[1])

        if (
            isNaN(width) ||
            isNaN(height) ||
            isNaN(refreshRate)
        ) {
            return null
        }

        return {
            width: width,
            height: height,
            refreshRate: refreshRate,
            refresh: refreshRate
        }
    }

    /*
     * ---------------------------------------------------------
     * Mode comparison
     * ---------------------------------------------------------
     */

    function modesEquivalent(
        firstMode,
        secondMode
    ) {
        var first =
            parseMode(firstMode)

        var second =
            parseMode(secondMode)

        if (
            !first ||
            !second
        ) {
            return false
        }

        if (
            first.width !==
                second.width ||
            first.height !==
                second.height
        ) {
            return false
        }

        /*
         * Hyprland may report the active refresh rate
         * slightly differently from availableModes.
         *
         * Example:
         *
         * available: 165.00
         * active:    165.002
         *
         * Treat those as equivalent.
         */
        return Math.abs(
            first.refreshRate -
            second.refreshRate
        ) < 0.1
    }

    function currentMode(monitor) {
        if (!monitor) {
            return ""
        }

        return normalizeMode(
            monitor.width +
            "x" +
            monitor.height +
            "@" +
            monitor.refreshRate
        )
    }

    /*
     * ---------------------------------------------------------
     * Mode validation
     * ---------------------------------------------------------
     */

    function modeExists(
        monitor,
        requestedMode
    ) {
        if (!monitor) {
            return false
        }

        if (
            !Array.isArray(
                monitor.availableModes
            )
        ) {
            return false
        }

        for (
            var i = 0;
            i <
                monitor.availableModes.length;
            i++
        ) {
            if (
                modesEquivalent(
                    monitor.availableModes[i],
                    requestedMode
                )
            ) {
                return true
            }
        }

        return false
    }

    function validateMode(
        monitorName,
        requestedMode
    ) {
        var monitor =
            findMonitor(
                monitorName
            )

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Monitor not found:",
                monitorName
            )

            return false
        }

        if (
            !modeExists(
                monitor,
                requestedMode
            )
        ) {
            console.warn(
                "[Battery Display Profiles] Mode not available:",
                requestedMode,
                "on",
                monitorName
            )

            return false
        }

        console.log(
            "[Battery Display Profiles] Mode validated:",
            monitorName,
            requestedMode
        )

        return true
    }

    /*
     * ---------------------------------------------------------
     * Lua string escaping
     * ---------------------------------------------------------
     */

    function escapeLuaString(value) {
        return String(value)
            .replace(
                /\\/g,
                "\\\\"
            )
            .replace(
                /"/g,
                '\\"'
            )
    }

    /*
     * ---------------------------------------------------------
     * Apply display mode
     * ---------------------------------------------------------
     */

    function applyMode(
        monitorName,
        requestedMode
    ) {
        if (
            commandProcess.running
        ) {
            console.warn(
                "[Battery Display Profiles] Cannot apply mode while another operation is running"
            )

            return false
        }

        var monitor =
            findMonitor(
                monitorName
            )

        if (!monitor) {
            console.warn(
                "[Battery Display Profiles] Cannot apply mode:",
                "monitor not found:",
                monitorName
            )

            modeApplyFailed(
                monitorName,
                requestedMode
            )

            return false
        }

        if (
            !modeExists(
                monitor,
                requestedMode
            )
        ) {
            console.warn(
                "[Battery Display Profiles] Refusing unavailable mode:",
                requestedMode,
                "on",
                monitorName
            )

            modeApplyFailed(
                monitorName,
                requestedMode
            )

            return false
        }

        var normalizedMode =
            normalizeMode(
                requestedMode
            )

        var lua =
            'hl.monitor({ output = "' +
            escapeLuaString(
                monitorName
            ) +
            '", mode = "' +
            escapeLuaString(
                normalizedMode
            ) +
            '" })'

        pendingMonitorName =
            monitorName

        pendingMode =
            normalizedMode

        operation = "apply"

        commandProcess.command = [
            "hyprctl",
            "eval",
            lua
        ]

        console.log(
            "[Battery Display Profiles] Applying mode:",
            monitorName,
            normalizedMode
        )

        console.log(
            "[Battery Display Profiles] Hyprland Lua:",
            lua
        )

        commandProcess.running = true

        return true
    }

    /*
     * ---------------------------------------------------------
     * Parse monitor discovery output
     *
     * IMPORTANT:
     *
     * We do NOT emit discoveryCompleted here.
     *
     * stdout finishing does not necessarily mean the
     * Process has emitted its exited signal yet.
     * We wait for onExited.
     * ---------------------------------------------------------
     */

    function handleDiscoveryData(
        data
    ) {
        var parsed

        try {
            parsed =
                JSON.parse(data)
        } catch (error) {
            var message =
                "Failed to parse hyprctl monitor JSON: " +
                error

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            pendingDiscoveryError =
                message

            pendingDiscoveryMonitors =
                null

            return
        }

        if (
            !Array.isArray(parsed)
        ) {
            var message =
                "Unexpected monitor data from hyprctl"

            console.warn(
                "[Battery Display Profiles]",
                message
            )

            pendingDiscoveryError =
                message

            pendingDiscoveryMonitors =
                null

            return
        }

        pendingDiscoveryMonitors =
            parsed

        pendingDiscoveryError = ""

        console.log(
            "[Battery Display Profiles] Discovered",
            parsed.length,
            "monitor(s)"
        )

        for (
            var i = 0;
            i < parsed.length;
            i++
        ) {
            var monitor =
                parsed[i]

            console.log(
                "[Battery Display Profiles] Monitor:",
                monitor.name,
                monitor.width +
                    "x" +
                    monitor.height,
                "@" +
                    monitor.refreshRate +
                    "Hz",
                "scale=" +
                    monitor.scale
            )

            if (
                Array.isArray(
                    monitor.availableModes
                )
            ) {
                console.log(
                    "[Battery Display Profiles] Available modes:",
                    monitor.availableModes.join(
                        ", "
                    )
                )
            }
        }
    }

    /*
     * ---------------------------------------------------------
     * Complete monitor discovery
     * ---------------------------------------------------------
     */

    function completeDiscovery() {
        if (
            pendingDiscoveryMonitors === null
        ) {
            var error =
                pendingDiscoveryError

            if (
                error === ""
            ) {
                error =
                    "No monitor data received"
            }

            console.warn(
                "[Battery Display Profiles] Discovery failed:",
                error
            )

            pendingDiscoveryError =
                ""

            if (pendingMonitorName !== "") {
                var failedMonitor = pendingMonitorName
                var failedMode = pendingMode
                pendingMonitorName = ""
                pendingMode = ""
                modeApplyFailed(
                    failedMonitor,
                    failedMode
                )
            }

            discoveryFailed(
                error
            )

            return
        }

        monitors =
            pendingDiscoveryMonitors

        pendingDiscoveryMonitors =
            null

        pendingDiscoveryError =
            ""

        console.log(
            "[Battery Display Profiles] Monitor discovery completed"
        )

        /*
         * If this discovery was triggered after applying a mode,
         * verify the target monitor's new mode before emitting
         * discoveryCompleted so listeners see the updated applied state.
         */
        if (pendingMonitorName !== "") {
            verifyAppliedMode()
        }

        /*
         * The Process has already exited at this point.
         *
         * It is now safe for listeners to start another
         * Process operation.
         */
        discoveryCompleted(
            monitors
        )
    }

    /*
     * ---------------------------------------------------------
     * Verify applied mode
     * ---------------------------------------------------------
     */

    function verifyAppliedMode() {
        var monitorName =
            pendingMonitorName

        var requestedMode =
            pendingMode

        var targetMonitor =
            findMonitor(
                monitorName
            )

        var actualMode =
            currentMode(
                targetMonitor
            )

        var verified =
            targetMonitor !== null &&
            modesEquivalent(
                actualMode,
                requestedMode
            )

        pendingMonitorName =
            ""

        pendingMode =
            ""

        if (verified) {
            console.log(
                "[Battery Display Profiles] Mode change verified:",
                monitorName,
                requestedMode
            )

            modeApplied(
                monitorName,
                requestedMode
            )

            return
        }

        console.warn(
            "[Battery Display Profiles] Mode change could not be verified:",
            "expected =",
            requestedMode,
            "actual =",
            actualMode
        )

        modeApplyFailed(
            monitorName,
            requestedMode
        )
    }

    /*
     * ---------------------------------------------------------
     * Process completion
     * ---------------------------------------------------------
     */

    function handleCommandExit(
        exitCode,
        exitStatus
    ) {
        var completedOperation =
            operation

        operation = ""

        console.log(
            "[Battery Display Profiles] hyprctl exited:",
            "operation =",
            completedOperation,
            "code =",
            exitCode,
            "status =",
            exitStatus
        )

        if (
            exitCode !== 0
        ) {
            var error =
                stderrCollector.text

            if (
                error.length === 0
            ) {
                error =
                    "hyprctl exited with code " +
                    exitCode
            }

            console.warn(
                "[Battery Display Profiles] hyprctl failed:",
                error
            )

            if (
                completedOperation ===
                "discover"
            ) {
                pendingDiscoveryMonitors =
                    null

                pendingDiscoveryError =
                    error

                completeDiscovery()

                return
            }

            if (
                completedOperation ===
                "apply"
            ) {
                var failedMonitor =
                    pendingMonitorName

                var failedMode =
                    pendingMode

                pendingMonitorName =
                    ""

                pendingMode =
                    ""

                modeApplyFailed(
                    failedMonitor,
                    failedMode
                )

                return
            }

            return
        }

        /*
         * Discovery completed successfully.
         *
         * This is intentionally the ONLY place where
         * discoveryCompleted is emitted.
         */
        if (
            completedOperation ===
            "discover"
        ) {
            completeDiscovery()

            return
        }

        /*
         * Mode application succeeded at the hyprctl
         * level. We now need a fresh monitor snapshot
         * before declaring success.
         */
        if (
            completedOperation ===
            "apply"
        ) {
            console.log(
                "[Battery Display Profiles] Mode command succeeded. Verifying..."
            )

            discoverMonitors()

            return
        }
    }

    /*
     * ---------------------------------------------------------
     * Hyprland process
     * ---------------------------------------------------------
     */

    Process {
        id: commandProcess

        stdout: StdioCollector {
            id: stdoutCollector

            onStreamFinished: {
                if (
                    root.operation ===
                    "discover"
                ) {
                    root.handleDiscoveryData(
                        text
                    )

                    return
                }

                if (
                    root.operation ===
                    "apply"
                ) {
                    console.log(
                        "[Battery Display Profiles] hyprctl eval output:",
                        text.trim()
                    )
                }
            }
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        onExited: function(
            exitCode,
            exitStatus
        ) {
            root.handleCommandExit(
                exitCode,
                exitStatus
            )
        }
    }

    Component.onCompleted: {
        root.discoverMonitors()
    }
}