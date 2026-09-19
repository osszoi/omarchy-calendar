import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// Clock, plus whatever meeting you are in and whatever meeting is about to
// start. Left click opens the calendar, right click walks the clock formats,
// middle click opens the timezone picker — the stock clock's bindings, because
// this widget replaces it.
//
// Clicking a meeting opens its link instead: joining is the one thing you do
// with a meeting that is about to start.
BarWidget {
  id: root
  moduleName: "eduardo.calendar"

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
  readonly property string syncBin: pluginDir + "/bin/omarchy-calendar-sync"
  readonly property string alertBin: pluginDir + "/bin/omarchy-calendar-alert"
  readonly property string authBin: pluginDir + "/bin/omarchy-calendar-auth"
  readonly property string accountBin: pluginDir + "/bin/omarchy-calendar-account"

  property date displayDate: clock.date
  property double nowEpoch: Math.floor(Date.now() / 1000)
  property double lastTickAt: Math.floor(Date.now() / 1000)

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")
  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  readonly property string clockText: Qt.formatDateTime(displayDate,
    configuredFormat.replace(/ww/g, Model.isoWeekLiteral(displayDate.getFullYear(), displayDate.getMonth(), displayDate.getDate())))
  readonly property var verticalLines: clockText.split("\n")

  readonly property var selection: Model.barSelection(store.events, nowEpoch, store.upcomingWindowMinutes)
  readonly property var ongoing: selection.ongoing
  readonly property var next: selection.next
  readonly property bool hasMeeting: !vertical && (ongoing !== null || next !== null)
  // The visual half of the alert: independent of the notification daemon, so a
  // silenced or covered toast still leaves something on screen.
  readonly property bool imminent: next !== null && (next.start - nowEpoch) <= 60

  function refresh() {
    displayDate = new Date()
    store.reload()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function sync() {
    Util.execArgv([root.syncBin])
  }

  function openEvent(event) {
    if (!event) return
    var url = String(event.link || event.htmlLink || "")
    if (url === "") return
    Util.execArgv(["omarchy-launch-browser", url])
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var nextFormat = Model.nextClockFormat(formatRing, current)
    if (nextFormat === "" || nextFormat === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = nextFormat

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Alerts. Recomputed from the freshest events every pass rather than
  //      scheduled ahead: a meeting that moved has to move its alert with it.
  function tick() {
    var now = Math.floor(Date.now() / 1000)
    var jumped = now - root.lastTickAt > 90
    root.lastTickAt = now
    root.nowEpoch = now

    // A jump that large is a suspend/resume, and the events on disk are as old
    // as the sleep was long. Sync before trusting them for anything.
    if (jumped) {
      root.sync()
      store.reload()
    }

    if (!store.everLoaded) return
    var due = Model.dueAlerts(store.events, now, store.leadMinutes, store.catchUpMinutes, store.fired)
    for (var i = 0; i < due.length; i++) root.fire(due[i])
  }

  function fire(alert) {
    var event = alert.event
    store.claimFired(alert.keys)

    var argv = [root.alertBin,
      "--keys", alert.keys.join(","),
      "--title", String(event.title || ""),
      "--when", String(event.start),
      "--end", String(event.end),
      "--lead", String(alert.lead),
      "--late", alert.late ? "1" : "0",
      "--account", String(event.account || "")]
    if (event.link) argv = argv.concat(["--link", String(event.link)])
    if (event.location) argv = argv.concat(["--location", String(event.location)])
    Util.execArgv(argv)
  }

  // ---- Calendar popup. Same shape contract the stock clock exposes, so the
  //      bar's popout coordinator and `omarchy-shell shell toggle` still work.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function toggleWeekStart() { if (panelLoader.item) panelLoader.item.toggleWeekStart() }

  readonly property real openPanelIndicatorWidth: button.labelWidth > 0 ? button.labelWidth : content.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = store
    if ("host" in target) target.host = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  CalendarData {
    id: store
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "eduardo.calendar"

    function refresh(): void { root.broadcast("refresh") }
    function sync(): void { root.sync() }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.clockText
    labelVisible: false
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : true
    fixedWidth: root.vertical ? -1 : content.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.hasMeeting ? meetingTooltip() : ""

    function meetingTooltip() {
      var lines = []
      if (root.ongoing)
        lines.push(Model.clockLabel(root.ongoing.start) + "–" + Model.clockLabel(root.ongoing.end)
          + "  " + root.ongoing.title + "  (" + root.ongoing.account + ")")
      if (root.next)
        lines.push(Model.clockLabel(root.next.start) + "–" + Model.clockLabel(root.next.end)
          + "  " + root.next.title + "  (" + root.next.account + ")")
      var joinable = (root.ongoing && root.ongoing.link) || (root.next && root.next.link)
      if (joinable) lines.push("Click a meeting to join")
      return lines.join("\n")
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }

    Row {
      id: content
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        id: clockLabel
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.clockText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      MeetingSegment {
        visible: root.ongoing !== null
        anchors.verticalCenter: parent.verticalCenter
        event: root.ongoing
        trailing: "now"
        foreground: button.foreground
        fontFamily: button.fontFamily
        fontSize: button.fontSize
        maxTitleChars: store.maxTitleChars
        onActivated: root.openEvent(root.ongoing)
      }

      MeetingSegment {
        visible: root.next !== null
        anchors.verticalCenter: parent.verticalCenter
        event: root.next
        trailing: root.next ? Model.relativeLabel(root.next.start - root.nowEpoch) : ""
        urgent: root.imminent
        urgentColor: root.bar ? root.bar.urgent : Color.urgent
        foreground: button.foreground
        fontFamily: button.fontFamily
        fontSize: button.fontSize
        maxTitleChars: store.maxTitleChars
        onActivated: root.openEvent(root.next)
      }
    }
  }
}
