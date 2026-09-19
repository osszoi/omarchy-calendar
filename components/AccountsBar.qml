import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The accounts, in precedence order — the order that decides which meeting
// owns the bar when two of them overlap. A chip is a button that opens its
// actions; nothing destructive or modal happens on the click itself.
Item {
  id: root

  property var store: null
  property string authBin: ""
  property string accountBin: ""
  property string syncBin: ""
  property double nowEpoch: 0
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property bool adding: false
  property string renaming: ""
  property string menuLabel: ""
  property bool confirmingRemoval: false
  property var menuAnchor: null

  readonly property bool editing: adding || renaming !== ""
  readonly property bool menuOpen: menuLabel !== ""
  readonly property var accounts: store ? (store.config.accounts || []) : []
  readonly property int authAge: store && store.auth && store.auth.at ? (root.nowEpoch - Number(store.auth.at)) : 99999
  readonly property bool waiting: store && store.auth && store.auth.state === "waiting" && authAge < 300
  readonly property string authError: store && store.auth && store.auth.state === "error" && authAge < 900 ? String(store.auth.message || "") : ""

  signal requestFocusRelease()

  implicitHeight: content.implicitHeight

  function openMenu(label, anchor) {
    if (root.menuLabel === label) { closeMenu(); return }
    root.renaming = ""
    root.confirmingRemoval = false
    root.menuAnchor = anchor
    root.menuLabel = label
  }

  function closeMenu() {
    root.menuLabel = ""
    root.confirmingRemoval = false
  }

  function accountAt(label) {
    for (var i = 0; i < root.accounts.length; i++)
      if (root.accounts[i].label === label) return { account: root.accounts[i], index: i }
    return null
  }

  function statusFor(label) {
    var state = root.store ? root.store.accountState(label) : null
    return state ? String(state.status || "ok") : "pending"
  }

  function startAdding() {
    closeMenu()
    root.adding = true
    Qt.callLater(function() {
      labelField.text = ""
      labelField.forceActiveFocus()
    })
  }

  function commitAdding() {
    var label = String(labelField.text || "").replace(/^\s+|\s+$/g, "")
    root.adding = false
    root.requestFocusRelease()
    Util.execArgv(label === "" ? [root.authBin, "--sync"] : [root.authBin, "--label", label, "--sync"])
  }

  function cancelAdding() {
    root.adding = false
    root.requestFocusRelease()
  }

  function startRenaming(label) {
    closeMenu()
    root.renaming = label
    Qt.callLater(function() {
      renameField.text = label
      renameField.selectAll()
      renameField.forceActiveFocus()
    })
  }

  function commitRenaming() {
    var from = root.renaming
    var to = String(renameField.text || "").replace(/^\s+|\s+$/g, "")
    root.renaming = ""
    root.requestFocusRelease()
    if (to === "" || to === from) return
    Util.execArgv([root.accountBin, from, "--rename", to])
  }

  function cancelRenaming() {
    root.renaming = ""
    root.requestFocusRelease()
  }

  function reauth(label) {
    closeMenu()
    Util.execArgv([root.authBin, "--label", label, "--sync"])
  }

  function move(label, direction) {
    closeMenu()
    Util.execArgv([root.accountBin, label, direction > 0 ? "--down" : "--up"])
  }

  function remove(label) {
    closeMenu()
    Util.execArgv([root.accountBin, label, "--remove"])
  }

  function syncNow() {
    closeMenu()
    Util.execArgv([root.syncBin])
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(6)

    Flow {
      id: chipRow
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.accounts

        Rectangle {
          id: chip
          required property var modelData
          required property int index

          readonly property string label: String(modelData.label || "")
          readonly property color accent: modelData.color || Color.accent
          readonly property string state: root.statusFor(label)
          readonly property bool broken: state !== "ok" && state !== "pending"
          readonly property bool active: root.menuLabel === label

          width: chipContent.implicitWidth + Style.space(16)
          height: Style.space(28)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
          color: chip.active || chipMouse.containsMouse
            ? Style.hoverFillFor(root.foreground, Color.accent)
            : Style.normalFillFor(root.foreground, Color.accent)
          border.width: chip.broken ? Style.spacing.hairline : 0
          border.color: Color.urgent

          Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: Style.space(5)

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(6)
              height: Style.space(6)
              radius: width / 2
              color: chip.accent
            }

            Text {
              textFormat: Text.PlainText
              visible: root.renaming !== chip.label
              anchors.verticalCenter: parent.verticalCenter
              text: chip.label
              color: chip.broken ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: renameField
              visible: root.renaming === chip.label
              width: Style.space(140)
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelRenaming()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitRenaming()
                  event.accepted = true
                }
              }
            }

            // A caret rather than a row of icons: the chip says "there is more
            // here", and what that is lives in the menu.
            Text {
              textFormat: Text.PlainText
              visible: root.renaming !== chip.label
              anchors.verticalCenter: parent.verticalCenter
              text: chip.active ? "▴" : "▾"
              color: Qt.darker(root.foreground, 1.7)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.renaming !== chip.label
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openMenu(chip.label, chip)
          }

          PanelToolTip {
            visible: chipMouse.containsMouse && !chip.active
            fontFamily: root.fontFamily
            text: {
              var state = root.store ? root.store.accountState(chip.label) : null
              var lines = [String(chip.modelData.email || chip.modelData.url || chip.label)]
              lines.push("precedence " + (chip.index + 1) + " of " + root.accounts.length)
              if (state && state.status !== "ok") lines.push(state.status + ": " + String(state.error || ""))
              return lines.join("\n")
            }
          }
        }
      }

      Rectangle {
        visible: !root.adding
        width: addRow.implicitWidth + Style.space(16)
        height: Style.space(28)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : height / 2
        color: addMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
        border.width: Style.spacing.hairline
        border.color: Style.normalBorderFor(root.foreground, Color.accent)

        Row {
          id: addRow
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            color: addMouse.containsMouse ? Color.accent : Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Add account"
            color: addMouse.containsMouse ? Color.accent : Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        MouseArea {
          id: addMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.store && root.store.clientSecretPresent
            ? root.startAdding()
            : Util.execArgv(["omarchy-launch-browser", "https://console.cloud.google.com/auth/clients"])
        }

        PanelToolTip {
          visible: addMouse.containsMouse
          fontFamily: root.fontFamily
          text: root.store && root.store.clientSecretPresent
            ? "Opens Google in the browser"
            : "No client_secret.json yet — opens the Google console (see README)"
        }
      }

      Row {
        visible: root.adding
        spacing: Style.space(6)

        TextField {
          id: labelField
          width: Style.space(160)
          anchors.verticalCenter: parent.verticalCenter
          placeholderText: "label, e.g. work"
          foreground: root.foreground
          font.family: root.fontFamily

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.cancelAdding()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.commitAdding()
              event.accepted = true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "enter to open Google"
          color: Qt.darker(root.foreground, 1.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      elide: Text.ElideRight
      text: {
        if (root.waiting) return "waiting for the browser…"
        if (root.authError === "missing-client-secret") return "add client_secret.json to ~/.config/omarchy-calendar"
        if (root.authError.indexOf("wrong-client-type") === 0) return "that client_secret.json is not a Desktop client"
        if (root.authError !== "") return "sign-in failed: " + root.authError
        if (!root.store || !root.store.everLoaded) return ""
        if (root.accounts.length === 0) return "no accounts yet"
        return "synced " + Model.staleness(root.store.syncedAt, root.nowEpoch).label
      }
      color: root.waiting || root.authError !== "" ? Color.urgent : Qt.darker(root.foreground, 2.0)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.syncNow()
      }
    }
  }

  // ---- The chip's actions. Opens upward, because the accounts sit at the
  //      bottom of the panel and a menu that fell off the edge would be worse
  //      than one that covers the month for a second.
  Item {
    id: actionMenu
    visible: root.menuOpen
    z: 100
    x: root.menuAnchor ? root.menuAnchor.x : 0
    y: (root.menuAnchor ? root.menuAnchor.y : 0) - menuCard.height - Style.space(6)
    width: menuCard.width
    height: menuCard.height

    readonly property var entry: root.accountAt(root.menuLabel)
    readonly property int index: entry ? entry.index : 0
    readonly property bool broken: root.menuOpen && root.statusFor(root.menuLabel) !== "ok"
                                   && root.statusFor(root.menuLabel) !== "pending"

    Rectangle {
      id: menuCard
      width: Style.space(190)
      height: menuColumn.implicitHeight + Style.space(10)
      radius: Style.cornerRadius
      color: Color.menu.background
      border.width: Math.max(1, Style.spacing.hairline)
      border.color: Util.alpha(root.foreground, 0.22)

      Column {
        id: menuColumn
        y: Style.space(5)
        width: parent.width
        spacing: 0

        Repeater {
          model: {
            var rows = []
            if (actionMenu.broken) rows.push({ id: "reauth", text: "Sign in again", urgent: true })
            rows.push({ id: "rename", text: "Rename" })
            rows.push({ id: "sync", text: "Sync now" })
            if (actionMenu.index > 0) rows.push({ id: "up", text: "Move up" })
            if (actionMenu.index < root.accounts.length - 1) rows.push({ id: "down", text: "Move down" })
            rows.push({ id: "remove", text: root.confirmingRemoval ? "Remove — sure?" : "Remove", urgent: true })
            return rows
          }

          Rectangle {
            required property var modelData

            width: menuColumn.width
            height: Style.space(26)
            color: rowMouse.containsMouse ? Color.menu.selectedBackground : "transparent"

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.text
              color: modelData.urgent
                ? (rowMouse.containsMouse ? Color.urgent : Qt.darker(Color.urgent, 1.15))
                : (rowMouse.containsMouse ? Color.menu.selectedText : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var label = root.menuLabel
                if (modelData.id === "rename") root.startRenaming(label)
                else if (modelData.id === "sync") root.syncNow()
                else if (modelData.id === "reauth") root.reauth(label)
                else if (modelData.id === "up") root.move(label, -1)
                else if (modelData.id === "down") root.move(label, 1)
                else if (modelData.id === "remove") {
                  // Two taps, because it also throws the token away.
                  if (root.confirmingRemoval) root.remove(label)
                  else root.confirmingRemoval = true
                }
              }
            }
          }
        }
      }
    }
  }
}
