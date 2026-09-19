import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// The calendar popup: the month on the left for "which day", the week on the
// right for "how does that day look", and the agenda under it for "what is it".
//
// The month is a read-out, as in the stock clock, with one addition: clicking a
// day takes the week grid to it. Nothing here edits a calendar.
Panel {
  id: root
  moduleName: "eduardo.calendar"
  ipcTarget: "eduardo.calendar"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var host: null
  property var store: null

  readonly property var barIdentity: hostWidget || root

  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property double selectedDay: Model.startOfDay(Math.floor(Date.now() / 1000))
  property double viewWeek: Model.weekStartEpoch(Math.floor(Date.now() / 1000), 1)

  readonly property double nowEpoch: host ? host.nowEpoch : Math.floor(Date.now() / 1000)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()
  readonly property bool onToday: selectedDay === Model.startOfDay(nowEpoch) && viewingCurrentMonth

  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property var events: store ? store.events : []
  readonly property var markers: Model.dayMarkers(events, 3)
  readonly property var dayEvents: Model.eventsForDay(events, selectedDay)
  readonly property string selectedKey: {
    var date = new Date(selectedDay * 1000)
    return Model.dateKey(date.getFullYear(), date.getMonth(), date.getDate())
  }

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) {
        setCenterHoverRevealSuppressed(true)
        weekGrid.scrollToNow()
      }
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    accounts.cancelAdding()
    accounts.cancelRenaming()
    accounts.closeMenu()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    if (root.store) root.store.reload()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedDay = Model.startOfDay(Math.floor(Date.now() / 1000))
    root.viewWeek = Model.weekStartEpoch(root.selectedDay, root.weekStart)
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Paging the week drags the selected day with it, so the agenda underneath
  // keeps answering for the day you were looking at rather than snapping back.
  function moveWeek(delta) {
    root.viewWeek = Model.addDays(root.viewWeek, delta * 7)
    root.selectedDay = Model.addDays(root.selectedDay, delta * 7)
    var date = new Date(root.selectedDay * 1000)
    root.viewYear = date.getFullYear()
    root.viewMonth = date.getMonth()
  }

  function selectDay(dayStart) {
    root.selectedDay = dayStart
    root.viewWeek = Model.weekStartEpoch(dayStart, root.weekStart)
  }

  function selectMonthDay(day) {
    selectDay(day.startEpoch)
    if (!day.inMonth) {
      root.viewYear = day.year
      root.viewMonth = day.month
    }
  }

  function openEvent(event) {
    if (root.host) root.host.openEvent(event)
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleWeekStart() {
    persistSettings({ weekStartDay: Model.weekStartSettingName(Model.toggledWeekStart(root.weekStart)) })
  }

  // The setting can also change from outside (shell.json is hot-reloaded), so
  // the displayed week follows the setting rather than whoever toggled it.
  onWeekStartChanged: root.viewWeek = Model.weekStartEpoch(root.selectedDay, root.weekStart)

  function weekRangeLabel() {
    var start = new Date(root.viewWeek * 1000)
    var end = new Date(Model.addDays(root.viewWeek, 6) * 1000)
    var sameMonth = start.getMonth() === end.getMonth()
    return "W" + Model.isoWeekForRange(root.viewWeek)
      + "  ·  " + Qt.formatDate(start, sameMonth ? "d" : "d MMM") + "–" + Qt.formatDate(end, "d MMM")
  }

  function agendaLabel() {
    if (root.selectedKey === root.todayKey) return "TODAY"
    return Qt.formatDate(new Date(root.selectedDay * 1000), "dddd d MMMM").toUpperCase()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.onToday
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(1700))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: accounts.editing
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: {
        if (accounts.menuOpen) accounts.closeMenu()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === ",") root.moveWeek(-1)
        else if (t === ".") root.moveWeek(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "r" || t === "R") { if (root.host) root.host.sync() }
      }

      Item {
        id: body
        anchors.fill: parent
        readonly property int weekHeight: Style.space(820)
        readonly property int agendaMinHeight: Style.space(220)

        implicitHeight: Math.max(
          leftColumn.implicitHeight + Style.space(16) + agendaMinHeight + Style.space(16) + accountsBlock.implicitHeight,
          weekHeader.height + Style.space(12) + weekHeight)

        // ---- Left: the month, and the accounts that feed everything here.
        Column {
          id: leftColumn
          width: monthGrid.implicitWidth
          spacing: Style.space(16)

          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(20)

              Text {
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 44
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.onToday
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          MonthGrid {
            id: monthGrid
            cellWidth: Style.space(72)
            cellHeight: Style.space(52)
            weekColumnWidth: Style.space(38)
            gutterWidth: Style.space(16)
            weeks: root.weeks
            markers: root.markers
            todayKey: root.todayKey
            selectedKey: root.selectedKey
            weekdays: root.weekdays
            nextWeekStartLabel: root.nextWeekStartLabel
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onDaySelected: function(day) { root.selectMonthDay(day) }
            onWeekStartToggled: root.toggleWeekStart()
            onMonthStepped: function(delta) { root.moveMonth(delta) }
          }

          Item {
            width: parent.width
            height: monthLabel.implicitHeight + Style.space(8)

            Text {
              id: monthLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: Style.space(220)
              horizontalAlignment: Text.AlignHCenter
              text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy").toUpperCase()
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.letterSpacing: 1
            }

            PanelActionButton {
              anchors.left: parent.left
              anchors.leftMargin: -Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅁"
              tooltipText: "Previous month"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.moveMonth(-1)
            }

            PanelActionButton {
              anchors.right: parent.right
              anchors.rightMargin: -Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅂"
              tooltipText: "Next month"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.moveMonth(1)
            }
          }

        }

        // The day the month is pointing at, spelled out. It lives in the rail
        // because that is where the space is: the week beside it is a full
        // panel tall, and this column had nothing under the month but air.
        Item {
          id: agendaArea
          x: 0
          y: leftColumn.implicitHeight + Style.space(16)
          width: leftColumn.width
          height: Math.max(0, accountsBlock.y - y - Style.space(16))
          clip: true

          Rectangle {
            id: agendaRule
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.1
          }

          Item {
            id: agendaHeaderRow
            y: Style.space(10)
            width: parent.width
            height: agendaHeader.implicitHeight + Style.space(4)

            Text {
              id: agendaHeader
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.agendaLabel()
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.dayEvents.length === 0 ? "" : root.dayEvents.length + (root.dayEvents.length === 1 ? " meeting" : " meetings")
              color: Qt.darker(root.contentForeground, 2.0)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Flickable {
            y: agendaHeaderRow.y + agendaHeaderRow.height + Style.space(6)
            width: parent.width
            height: parent.height - y
            contentWidth: width
            contentHeight: agenda.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            AgendaList {
              id: agenda
              width: parent.width
              events: root.dayEvents
              nowEpoch: root.nowEpoch
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              emptyText: root.selectedKey === root.todayKey ? "Nothing else today" : "Nothing scheduled"
              onEventActivated: function(event) { root.openEvent(event) }
            }
          }
        }

        // Pinned to the bottom of its column rather than left hanging under
        // the month: the week beside it is taller, and a settings row floating
        // in the middle of empty space reads like something went wrong.
        Column {
          id: accountsBlock
          width: leftColumn.width
          anchors.bottom: body.bottom
          spacing: Style.space(8)

          Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: root.contentForeground
            opacity: 0.1
          }

          AccountsBar {
            id: accounts
            width: parent.width
            store: root.store
            nowEpoch: root.nowEpoch
            authBin: root.host ? root.host.authBin : ""
            accountBin: root.host ? root.host.accountBin : ""
            syncBin: root.host ? root.host.syncBin : ""
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onRequestFocusRelease: Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }

        Rectangle {
          x: leftColumn.width + Style.space(26)
          width: Style.spacing.hairline
          height: body.height
          color: root.contentForeground
          opacity: 0.1
        }

        // ---- Right: the week, filling the panel.
        Item {
          id: rightColumn
          x: leftColumn.width + Style.space(52)
          width: body.width - x
          anchors.top: body.top
          anchors.bottom: body.bottom

          Item {
            id: weekHeader
            width: parent.width
            height: Style.space(34)

            Text {
              id: weekLabel
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.weekRangeLabel()
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.letterSpacing: 1
            }

            PanelActionButton {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅁"
              tooltipText: "Previous week"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.moveWeek(-1)
            }

            PanelActionButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅂"
              tooltipText: "Next week"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.moveWeek(1)
            }
          }

          WeekGrid {
            id: weekGrid
            width: parent.width
            y: weekHeader.height + Style.space(12)
            height: parent.height - y
            hourHeight: Style.space(52)
            gutterWidth: Style.space(50)
            events: root.events
            weekStart: root.viewWeek
            nowEpoch: root.nowEpoch
            todayKey: root.todayKey
            selectedKey: root.selectedKey
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onEventActivated: function(event) { root.openEvent(event) }
            onDaySelected: function(dayStart) { root.selectDay(dayStart) }
          }

        }
      }
    }
  }

  Connections {
    target: root
    function onOpenedChanged() {
      if (root.opened) Qt.callLater(function() { weekGrid.scrollToNow() })
    }
  }
}
