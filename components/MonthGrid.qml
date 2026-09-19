import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Month read-out, adapted from omarchy's clock panel (MIT): week numbers down
// a gutter, six fixed rows so the popup never changes height. Days carry a dot
// per account that has something on them, and clicking one takes the week grid
// beside it to that week.
Item {
  id: root

  property var weeks: []
  property var markers: ({})
  property string todayKey: ""
  property string selectedKey: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var weekdays: [1, 2, 3, 4, 5, 6, 0]
  property string nextWeekStartLabel: "Sunday"

  property int cellWidth: Style.space(40)
  property int cellHeight: Style.space(30)
  property int cellSpacing: Style.space(2)
  property int weekColumnWidth: Style.space(26)
  property int gutterWidth: Style.space(10)

  signal daySelected(var day)
  signal weekStartToggled()
  signal monthStepped(int delta)

  readonly property var labelLocale: Qt.locale("en_US")

  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  implicitWidth: grid.width
  implicitHeight: grid.height

  WheelHandler {
    onWheel: function(event) {
      if (event.angleDelta.y === 0) return
      root.monthStepped(event.angleDelta.y > 0 ? -1 : 1)
    }
  }

  Column {
    id: grid
    spacing: Style.space(3)

    Row {
      id: headerRow
      spacing: root.cellSpacing

      Rectangle {
        width: root.weekColumnWidth
        height: Style.space(22)
        radius: Style.cornerRadius
        color: weekStartMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

        Text {
          anchors.centerIn: parent
          text: "W"
          color: weekStartMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : Qt.darker(root.foreground, 1.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
          font.bold: true
        }

        MouseArea {
          id: weekStartMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.weekStartToggled()
        }

        PanelToolTip {
          visible: weekStartMouse.containsMouse
          text: "Start weeks on " + root.nextWeekStartLabel
          fontFamily: root.fontFamily
        }
      }

      Item {
        width: root.gutterWidth
        height: Style.space(22)
      }

      Repeater {
        model: root.weekdays

        Text {
          required property var modelData
          textFormat: Text.PlainText
          width: root.cellWidth
          height: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: root.weekdayLabel(modelData)
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
          font.bold: true
        }
      }
    }

    Repeater {
      model: root.weeks

      Row {
        required property var modelData
        spacing: root.cellSpacing

        Text {
          textFormat: Text.PlainText
          width: root.weekColumnWidth
          height: root.cellHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData.week
          color: Qt.darker(root.foreground, 1.9)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          width: root.gutterWidth
          height: root.cellHeight
        }

        Repeater {
          model: modelData.days

          Rectangle {
            id: cell
            required property var modelData

            readonly property var marker: root.markers[modelData.key]
            readonly property bool selected: modelData.key === root.selectedKey

            width: root.cellWidth
            height: root.cellHeight
            radius: Style.cornerRadius
            color: selected && !modelData.today
              ? Style.selectedFillFor(root.foreground, Color.accent)
              : (dayMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
            border.width: modelData.today ? Style.spacing.hairline : 0
            border.color: Style.normalBorderFor(root.foreground, Color.accent)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              anchors.verticalCenterOffset: -Style.space(5)
              text: modelData.day
              color: modelData.inMonth
                ? (modelData.weekend ? Qt.darker(root.foreground, 1.45) : root.foreground)
                : Qt.darker(root.foreground, 2.2)
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: modelData.today
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(6)
              spacing: Style.space(2)

              Repeater {
                model: cell.marker ? cell.marker.colors : []

                Rectangle {
                  required property var modelData
                  width: Style.space(5)
                  height: Style.space(5)
                  radius: width / 2
                  color: modelData
                  opacity: cell.modelData.inMonth ? 0.95 : 0.4
                }
              }
            }

            MouseArea {
              id: dayMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.daySelected(cell.modelData)
            }
          }
        }
      }
    }
  }

  // Hairline down the week-number gutter, beside the day rows only.
  Rectangle {
    x: root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
    y: headerRow.height + grid.spacing
    width: Style.spacing.hairline
    height: grid.height - headerRow.height - grid.spacing
    color: root.foreground
    opacity: 0.1
  }
}
