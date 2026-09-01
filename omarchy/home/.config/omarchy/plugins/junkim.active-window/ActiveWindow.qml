import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.active-window"


  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property var applications: DesktopEntries.applications.values || []
  readonly property string appId: toplevel ? String(toplevel.appId || "") : ""
  readonly property string windowTitle: toplevel ? String(toplevel.title || "") : ""
  readonly property string appName: resolveAppName(appId, windowTitle, applications)
  readonly property string title: windowTitle || appName
  readonly property int maxLabelWidth: Number(setting("maxWidth", 280))

  function normalizedId(value) {
    return String(value || "").replace(/\.desktop$/i, "").toLowerCase()
  }

  function fallbackName(value) {
    var raw = String(value || "").replace(/\.desktop$/i, "")
    var appMode = /^chrome-app\./i.test(raw) || raw.indexOf("__") !== -1
    var host = raw.replace(/^chrome-app\./i, "").split("__")[0]
    var hostParts = host.split(".")
    var appLabel = appMode && hostParts.length > 1 ? hostParts[hostParts.length - 2] : ""
    var leaf = appLabel || raw.split(".").pop() || raw
    var words = leaf.replace(/[-_]+/g, " ").replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    return words.replace(/\b\w/g, function(character) { return character.toUpperCase() })
  }

  function resolveAppName(value, windowTitle, entries) {
    var target = normalizedId(value)
    if (!target) return ""
    if (target.indexOf("slack") !== -1 || (target.indexOf("zen") !== -1 && /\bslack\b/i.test(windowTitle))) return "Slack"

    for (var i = 0; i < entries.length; i++) {
      if (normalizedId(entries[i].id) === target) return String(entries[i].name || entries[i].id)
    }

    var targetLeaf = target.split(".").pop()
    for (var j = 0; j < entries.length; j++) {
      var entryId = normalizedId(entries[j].id)
      if (entryId.split(".").pop() === targetLeaf) return String(entries[j].name || entries[j].id)
    }

    return fallbackName(value)
  }

  visible: appName !== "" && !vertical
  implicitWidth: visible ? Math.min(maxLabelWidth, labelText.implicitWidth) + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    clip: true

    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: parent.width
      text: root.appName
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      opacity: 0.85
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (!root.toplevel) return
      if (mouse.button === Qt.MiddleButton) {
        root.toplevel.close()
      } else if (mouse.button === Qt.RightButton) {
        root.toplevel.close()
      } else {
        root.toplevel.activate()
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.title)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
