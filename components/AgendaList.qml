import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// What is left of a day, spelled out. The week grid answers "how busy", this
// answers "what is it and can I click it".
Column {
  id: root

  property var events: []
  property double nowEpoch: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string emptyText: "Nothing scheduled"

  signal eventActivated(var event)

  spacing: Style.space(2)

  Text {
    textFormat: Text.PlainText
    visible: root.events.length === 0
    text: root.emptyText
    color: Qt.darker(root.foreground, 2.0)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.events

    Rectangle {
      id: row
      required property var modelData

      readonly property bool ongoing: !modelData.allDay && root.nowEpoch >= modelData.start && root.nowEpoch < modelData.end
      readonly property bool past: !modelData.allDay && modelData.end <= root.nowEpoch
      readonly property color accent: modelData.color || Color.accent

      width: root.width
      height: Style.space(30)
      radius: Style.cornerRadius
      color: rowMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
      opacity: past ? 0.45 : 1

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(52)
          text: row.modelData.allDay ? "all day" : Model.clockLabel(row.modelData.start)
          color: row.ongoing ? root.foreground : Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.ongoing
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(2, Style.space(2))
          height: Style.space(16)
          radius: width / 2
          color: row.accent
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(Style.space(40), row.width - Style.space(260))
          elide: Text.ElideRight
          text: row.modelData.title
          color: rowMouse.containsMouse && (row.modelData.link || row.modelData.htmlLink)
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.ongoing
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.allDay ? "" : (row.ongoing ? "now" : (row.modelData.start > root.nowEpoch ? Model.relativeLabel(row.modelData.start - root.nowEpoch) : ""))
          color: row.ongoing ? Color.urgent : Qt.darker(root.foreground, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.account
        color: Util.alpha(row.accent, 0.85)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: (row.modelData.link || row.modelData.htmlLink) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.eventActivated(row.modelData)
      }

      PanelToolTip {
        visible: rowMouse.containsMouse
        fontFamily: root.fontFamily
        text: (row.modelData.allDay ? "all day" : Model.clockLabel(row.modelData.start) + "–" + Model.clockLabel(row.modelData.end))
          + "  " + row.modelData.title
          + (row.modelData.location ? "\n" + row.modelData.location : "")
          + (row.modelData.link ? "\nclick to join" : "")
      }
    }
  }
}
