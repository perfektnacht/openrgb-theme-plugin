import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless service: watches for a theme switch and repaints every OpenRGB
// device to match. Color.accent is a live property on the shell's Commons
// singleton -- the shell pushes new values through IPC on a theme switch -- so
// binding to it is all the change notification this needs.
//
// The accent is only the *trigger*. Which colour the devices get is the
// helper's decision: it looks the theme up in its own hand-picked table and
// only falls back to the accent for themes it doesn't know. This service used
// to pass --color and in doing so would now bypass that table entirely.
//
// Settings deliberately live in the helper, not here. The helper runs on every
// apply and reads shell.json itself, so config is always current without a file
// watcher. An earlier version watched shell.json from QML and served stale
// values whenever a writer truncated the file before rewriting it.
Item {
  id: root

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  readonly property string helper: Qt.resolvedUrl("bin/omarchy-openrgb-theme").toString().replace("file://", "")

  // All three are read back from the helper, which is the only side that knows
  // what it picked. lastOrigin is "theme:<slug>" for a table hit or "accent"
  // for the fallback; lastRequested is the colour that path chose and
  // lastApplied is what reached the LEDs. Those two differ only on the accent
  // path, where the saturation lift moves the colour -- reporting the request
  // as the result once made a pastel theme look like it had been sent verbatim.
  property string lastOrigin: ""
  property string lastRequested: ""
  property string lastApplied: ""
  property bool applyPending: false

  // Color.accent is a `color`, not the original hex string. Round-trip it back
  // to RRGGBB so the helper does the saturation maths on the same value.
  function accentHex() {
    var c = Color.accent
    function byte(v) {
      var s = Math.round(v * 255).toString(16).toUpperCase()
      return s.length < 2 ? "0" + s : s
    }
    return byte(c.r) + byte(c.g) + byte(c.b)
  }

  function apply() {
    // The accent still gates the call. A black accent means Commons has not
    // resolved a palette yet, and firing then would paint the devices off.
    var hex = accentHex()
    if (!hex || hex === "000000") return

    // Coalesce: a theme switch can retint several properties in one tick, and
    // openrgb is a single-writer path. Let the in-flight write finish, then
    // re-run once for whatever the theme settled on.
    if (applyProcess.running) {
      applyPending = true
      return
    }
    // No --color: the helper resolves the theme itself. Passing one here would
    // take the explicit-override path and skip the per-theme table.
    applyProcess.command = [root.helper]
    applyProcess.running = true
  }

  // Debounce the binding itself so a theme switch is one hardware write, not one
  // per intermediate property update.
  Timer {
    id: debounce
    interval: 150
    onTriggered: root.apply()
  }

  Connections {
    target: Color
    function onAccentChanged() { debounce.restart() }
  }

  Process {
    id: applyProcess
    stdout: StdioCollector {
      waitForEnd: true
      // "<origin> <source> <final>" on a successful apply.
      onStreamFinished: {
        var found = text.trim().match(/^(\S+) ([0-9A-Fa-f]{6}) ([0-9A-Fa-f]{6})$/)
        if (!found) return
        root.lastOrigin = found[1]
        root.lastRequested = found[2].toUpperCase()
        root.lastApplied = found[3].toUpperCase()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.length > 0) console.warn("openrgb-theme:", text.trim())
    }
    onExited: function(exitCode) {
      if (root.applyPending) {
        root.applyPending = false
        root.apply()
        return
      }
      if (exitCode !== 0) console.warn("openrgb-theme: helper exited", exitCode)
    }
  }

  Component.onCompleted: debounce.restart()

  // ------------------------------------------------------------------ IPC
  IpcHandler {
    target: "openrgb-theme"

    // Reapply on demand -- useful from a resume hook, since Direct mode does
    // not survive a suspend on every device.
    // Returns the *previous* apply's colour: the helper only reports what it
    // sent once it has exited, which is after this returns.
    function apply(): string {
      root.apply()
      return root.lastApplied
    }

    function status(): string {
      return JSON.stringify({
        accent: root.accentHex(),
        origin: root.lastOrigin,
        lastRequested: root.lastRequested,
        lastApplied: root.lastApplied
      })
    }
  }
}
