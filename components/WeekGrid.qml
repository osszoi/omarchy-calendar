import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The week, the way a calendar app draws it: a column per day, an hour rail
// down the side, and overlapping meetings sharing the width of their cluster
// instead of hiding behind each other.
Item {
  id: root

  property var events: []
  property double weekStart: 0
  property int dayCount: 7
  property double nowEpoch: 0
  property string todayKey: ""
  property string selectedKey: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int hourHeight: Style.space(52)
  property int gutterWidth: Style.space(50)

  signal eventActivated(var event)
  signal daySelected(double dayStart)

  readonly property var layout: Model.weekLayout(events, weekStart, dayCount)
  readonly property var allDay: Model.allDayLayout(events, weekStart, dayCount)
  readonly property int allDayRows: {
    var most = 0
    for (var i = 0; i < allDay.length; i++) most = Math.max(most, allDay[i].events.length)
    return Math.min(most, 3)
  }
  readonly property real columnWidth: Math.floor((width - gutterWidth) / dayCount)
  readonly property var labelLocale: Qt.locale("en_US")

  // Hour-of-day of the first event in the week that has not finished yet, or
  // of the earliest one if the whole week is behind us.
  function firstRelevantHour() {
    var upcoming = 0
    var earliest = 0
    for (var d = 0; d < root.layout.length; d++) {
      var day = root.layout[d]
      for (var i = 0; i < day.events.length; i++) {
        var start = day.events[i].start
        if (earliest === 0 || start < earliest) earliest = start
        if (day.events[i].end <= root.nowEpoch) continue
        if (upcoming === 0 || start < upcoming) upcoming = start
      }
    }
    var anchor = upcoming || earliest
    if (anchor === 0) return -1
    var date = new Date(anchor * 1000)
    return date.getHours() + date.getMinutes() / 60
  }

  // Anchored on now, except when that would leave every meeting below the
  // fold — at 00:15 on a Sunday "now" is a wall of empty night, and the week
  // looks broken rather than quiet.
  function scrollToNow() {
    var now = new Date(root.nowEpoch * 1000)
    var nowHour = now.getHours() + now.getMinutes() / 60
    var viewportHours = root.hourHeight > 0 ? flick.height / root.hourHeight : 8
    var eventHour = firstRelevantHour()

    var targetHour = nowHour - 2
    if (eventHour >= 0 && eventHour > nowHour + viewportHours - 1.5)
      targetHour = eventHour - 1

    var max = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(max, targetHour * root.hourHeight))
  }

  // Paging to another week re-anchors it; otherwise you land in last week's
  // scroll position and think it is empty.
  onWeekStartChanged: Qt.callLater(scrollToNow)

  function dayLabel(dayStart) {
    var date = new Date(dayStart * 1000)
    return String(labelLocale.dayName(date.getDay(), Locale.ShortFormat)).toUpperCase()
  }

  function dayNumber(dayStart) {
    return new Date(dayStart * 1000).getDate()
  }

  function dayKey(dayStart) {
    var date = new Date(dayStart * 1000)
    return Model.dateKey(date.getFullYear(), date.getMonth(), date.getDate())
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(4)

    Row {
      id: header
      width: parent.width
      height: Style.space(30)

      Item {
        width: root.gutterWidth
        height: parent.height
      }

      Repeater {
        model: root.layout

        Item {
          required property var modelData
          readonly property string key: root.dayKey(modelData.dayStart)
          readonly property bool isToday: key === root.todayKey

          width: root.columnWidth
          height: header.height

          Rectangle {
            anchors.centerIn: parent
            width: dayText.implicitWidth + Style.space(12)
            height: parent.height - Style.space(2)
            radius: Style.cornerRadius
            color: parent.isToday
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : (key === root.selectedKey ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
          }

          Text {
            id: dayText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.dayLabel(modelData.dayStart) + " " + root.dayNumber(modelData.dayStart)
            color: parent.isToday ? root.foreground : Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            font.bold: parent.isToday
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.daySelected(modelData.dayStart)
          }
        }
      }
    }

    Item {
      id: allDayStrip
      width: parent.width
      height: root.allDayRows > 0 ? root.allDayRows * Style.space(20) + Style.space(6) : 0
      visible: height > 0

      Text {
        textFormat: Text.PlainText
        x: 0
        y: Style.space(2)
        width: root.gutterWidth - Style.space(6)
        horizontalAlignment: Text.AlignRight
        text: "all day"
        color: Qt.darker(root.foreground, 2.1)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        x: root.gutterWidth
        width: parent.width - root.gutterWidth
        height: parent.height

        Repeater {
          model: root.allDay

          Column {
            required property var modelData
            width: root.columnWidth
            height: allDayStrip.height
            spacing: Style.space(2)

            Repeater {
              model: modelData.events.slice(0, root.allDayRows)

              Rectangle {
                required property var modelData
                width: root.columnWidth - Style.space(4)
                height: Style.space(18)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(2)
                color: Util.alpha(modelData.color || Color.accent, allDayMouse.containsMouse ? 0.34 : 0.18)

                Text {
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(5)
                  anchors.rightMargin: Style.space(3)
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                  text: modelData.title
                  color: Qt.darker(root.foreground, 1.15)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: allDayMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.eventActivated(parent.modelData)
                }

                PanelToolTip {
                  visible: allDayMouse.containsMouse
                  fontFamily: root.fontFamily
                  text: parent.modelData.title + "\n" + parent.modelData.account + " · all day"
                }
              }
            }
          }
        }
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.gutterWidth
        height: Style.spacing.hairline
        color: root.foreground
        opacity: 0.12
      }
    }

    Flickable {
      id: flick
      width: parent.width
      height: parent.height - header.height - allDayStrip.height - Style.space(4) - (allDayStrip.visible ? Style.space(4) : 0)
      contentWidth: width
      contentHeight: 24 * root.hourHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Item {
        width: flick.width
        height: flick.contentHeight

        Repeater {
          model: 24

          Item {
            required property int index
            y: index * root.hourHeight
            width: flick.width
            height: root.hourHeight

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: root.gutterWidth
              height: Style.spacing.hairline
              color: root.foreground
              opacity: 0.08
            }

            Text {
              textFormat: Text.PlainText
              visible: index > 0
              x: 0
              y: -implicitHeight / 2
              width: root.gutterWidth - Style.space(6)
              horizontalAlignment: Text.AlignRight
              text: Model.pad2(index)
              color: Qt.darker(root.foreground, 2.1)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        Repeater {
          model: root.layout

          Item {
            required property var modelData
            required property int index

            x: root.gutterWidth + index * root.columnWidth
            y: 0
            width: root.columnWidth
            height: flick.contentHeight

            Rectangle {
              anchors.fill: parent
              color: root.dayKey(modelData.dayStart) === root.selectedKey
                ? Style.hoverFillFor(root.foreground, Color.accent)
                : "transparent"
              opacity: 0.5
            }

            Rectangle {
              anchors.left: parent.left
              width: Style.spacing.hairline
              height: parent.height
              color: root.foreground
              opacity: 0.08
            }

            Repeater {
              model: modelData.events

              Rectangle {
                id: block
                required property var modelData

                readonly property var event: modelData.event
                readonly property color accent: event.color || Color.accent
                readonly property bool ongoing: root.nowEpoch >= event.start && root.nowEpoch < event.end
                readonly property real slotWidth: (root.columnWidth - Style.space(3)) / modelData.columns

                x: Style.space(2) + modelData.column * slotWidth
                y: (modelData.start - modelData.dayStart) / 3600 * root.hourHeight
                width: Math.max(Style.space(10), slotWidth - Style.space(1))
                height: Math.max(Style.space(20), (modelData.end - modelData.start) / 3600 * root.hourHeight - Style.space(1))
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(2)
                color: Util.alpha(accent, blockMouse.containsMouse ? 0.32 : (ongoing ? 0.26 : 0.16))
                border.width: ongoing ? Style.spacing.hairline : 0
                border.color: Util.alpha(accent, 0.9)

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Math.max(2, Style.space(2))
                  radius: parent.radius
                  color: block.accent
                }

                Column {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(3)
                  anchors.topMargin: Style.space(2)
                  spacing: 0
                  clip: true

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: block.event.title
                    elide: Text.ElideRight
                    maximumLineCount: block.height > Style.space(54) ? 2 : 1
                    wrapMode: Text.NoWrap
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: block.ongoing
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: block.height > Style.space(48)
                    width: parent.width
                    text: Model.clockLabel(block.event.start) + "–" + Model.clockLabel(block.event.end)
                    elide: Text.ElideRight
                    color: Qt.darker(root.foreground, 1.6)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  id: blockMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.eventActivated(block.event)
                }

                PanelToolTip {
                  visible: blockMouse.containsMouse
                  fontFamily: root.fontFamily
                  text: Model.clockLabel(block.event.start) + "–" + Model.clockLabel(block.event.end)
                    + "  " + block.event.title + "\n" + block.event.account
                    + (block.event.link ? "  ·  click to join" : "")
                }
              }
            }
          }
        }

        // Now, drawn across the whole week rather than only today's column:
        // the line is how you read "where am I in the day" at a glance.
        Item {
          visible: root.nowEpoch >= root.weekStart && root.nowEpoch < Model.addDays(root.weekStart, root.dayCount)
          width: flick.width
          y: {
            var date = new Date(root.nowEpoch * 1000)
            return (date.getHours() + date.getMinutes() / 60) * root.hourHeight
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.gutterWidth
            height: Math.max(1, Style.spacing.hairline)
            color: Color.urgent
            opacity: 0.85
          }

          Rectangle {
            x: root.gutterWidth - Style.space(3)
            y: -Style.space(3)
            width: Style.space(6)
            height: Style.space(6)
            radius: width / 2
            color: Color.urgent
          }
        }
      }
    }
  }
}
