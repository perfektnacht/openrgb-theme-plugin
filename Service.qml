import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Headless service: watches the theme accent and repaints every OpenRGB device
// to match. Color.accent is a live property on the shell's Commons singleton --
// the shell pushes new values through IPC on a theme switch -- so binding to it
// is all the change notification this needs.
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

  // lastRequested is the theme accent this asked for; lastApplied is what the
  // helper reports actually reaching the LEDs, which differs whenever the
  // saturation floor kicks in. Reporting the request as the result made a
  // pastel theme look like it had been sent verbatim.
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
    var hex = accentHex()
    if (!hex || hex === "000000") return

    root.lastRequested = hex

    // Coalesce: a theme switch can retint several properties in one tick, and
    // openrgb is a single-writer path. Let the in-flight write finish, then
    // re-run once for whatever the accent settled on.
    if (applyProcess.running) {
      applyPending = true
      return
    }
    applyProcess.command = [root.helper, "--color", hex]
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
      // The helper prints the post-saturation colour on a successful apply.
      onStreamFinished: {
        var out = text.trim()
        if (/^[0-9A-Fa-f]{6}$/.test(out)) root.lastApplied = out.toUpperCase()
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
    // Returns the requested colour, not the applied one: the helper only
    // reports what it sent once it has exited, which is after this returns.
    function apply(): string {
      root.apply()
      return root.lastRequested
    }

    function status(): string {
      return JSON.stringify({
        accent: root.accentHex(),
        lastRequested: root.lastRequested,
        lastApplied: root.lastApplied
      })
    }
  }
}
