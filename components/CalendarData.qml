import QtQuick
import Quickshell
import Quickshell.Io

// Everything the widget and the panel read comes from disk: the sync helper
// owns the events, the auth helper owns the accounts, and this just keeps the
// parsed copy in step with the files.
//
// Reloads are both watched and polled. An atomic replace (rename over the
// path) is exactly the write pattern a file watcher can miss, and a bar that
// silently stops updating is worse than a reload that was not needed.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: home + "/.cache/omarchy-calendar"
  readonly property string configDir: home + "/.config/omarchy-calendar"

  property var events: []
  property var accounts: []
  property var config: ({})
  property var fired: ({})
  property var auth: ({})
  property double syncedAt: 0
  property bool everLoaded: false
  property bool clientSecretPresent: false

  readonly property var leadMinutes: config.leadMinutes || [5, 1]
  readonly property int upcomingWindowMinutes: Number(config.upcomingWindowMinutes || 60)
  readonly property int catchUpMinutes: Number(config.catchUpMinutes || 10)
  readonly property int maxTitleChars: Number(config.maxTitleChars || 28)
  readonly property bool configured: (config.accounts || []).length > 0

  // Per-account colour, looked up more often than anything else here.
  function accountColor(label) {
    for (var i = 0; i < accounts.length; i++)
      if (accounts[i].label === label) return accounts[i].color || "#7aa2f7"
    var configured = config.accounts || []
    for (var c = 0; c < configured.length; c++)
      if (configured[c].label === label) return configured[c].color || "#7aa2f7"
    return "#7aa2f7"
  }

  function accountState(label) {
    for (var i = 0; i < accounts.length; i++)
      if (accounts[i].label === label) return accounts[i]
    return null
  }

  function reload() {
    eventsFile.reload()
    configFile.reload()
    firedFile.reload()
    statusFile.reload()
    secretFile.reload()
  }

  // Claimed locally the moment we launch the alert helper, so the next tick
  // does not fire the same meeting again while the helper is still starting.
  function claimFired(keys) {
    var next = {}
    for (var key in root.fired) next[key] = root.fired[key]
    for (var i = 0; i < keys.length; i++) next[keys[i]] = 1
    root.fired = next
  }

  function applyEvents(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      root.events = parsed.events || []
      root.accounts = parsed.accounts || []
      root.syncedAt = Number(parsed.syncedAt || 0)
      root.everLoaded = true
    } catch (e) {
      console.warn("[eduardo.calendar] events.json unreadable: " + e)
    }
  }

  FileView {
    id: eventsFile
    path: root.cacheDir + "/events.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyEvents(text())
    onFileChanged: reload()
    onLoadFailed: root.everLoaded = true
  }

  FileView {
    id: configFile
    path: root.configDir + "/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text() || "{}") } catch (e) { root.config = ({}) }
    }
    onLoadFailed: root.config = ({})
  }

  FileView {
    id: firedFile
    path: root.cacheDir + "/alerted.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.fired = JSON.parse(text() || "{}") } catch (e) { root.fired = ({}) }
    }
    onLoadFailed: root.fired = ({})
  }

  FileView {
    id: statusFile
    path: root.cacheDir + "/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.auth = JSON.parse(text() || "{}") } catch (e) { root.auth = ({}) }
    }
    onLoadFailed: root.auth = ({})
  }

  FileView {
    id: secretFile
    path: root.configDir + "/client_secret.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.clientSecretPresent = String(text() || "").length > 0
    onLoadFailed: root.clientSecretPresent = false
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.reload()
  }
}
