import QtQuick
import qs.Commons
import "../Model.js" as Model

// One meeting in the bar: a dot in its account's colour, the title, and when
// it is. The dot doubles as the separator from the clock, which is quieter
// than a bullet plus a colour swatch sitting next to each other.
Item {
  id: root

  property var event: null
  property string trailing: ""
  property bool urgent: false
  property color foreground: Color.foreground
  property color urgentColor: Color.urgent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property int maxTitleChars: 28

  signal activated()

  readonly property string title: event ? Model.truncate(event.title, maxTitleChars) : ""
  readonly property color dotColor: event && event.color ? event.color : Color.accent
  readonly property bool joinable: !!(event && (event.link || event.htmlLink))

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(4, Math.round(root.fontSize * 0.42))
      height: width
      radius: width / 2
      color: root.dotColor
      opacity: mouse.containsMouse ? 1 : 0.9
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
      color: mouse.containsMouse && root.joinable
        ? Style.hoverStateColor(root.foreground, Color.accent)
        : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.trailing
      color: root.urgent ? root.urgentColor : Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
    }
  }

  // The last minute, said without a notification: a pulse the eye catches
  // even when the toast is behind a fullscreen window or silenced.
  SequentialAnimation on opacity {
    running: root.urgent
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
    onStopped: root.opacity = 1
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.joinable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton
    onClicked: root.activated()
    propagateComposedEvents: !root.joinable
  }
}
