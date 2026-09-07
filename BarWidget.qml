import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.ef-code.wallpaper-explorer"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰋩"
    tooltipText: "Wallpaper Explorer"
    active: root.bar && root.bar.shell ? root.bar.shell.isPluginOpen(root.moduleName) : false
    useActiveColor: true
    activeColor: Color.accent

    onPressed: function(buttonCode) {
      if (!root.bar || !root.bar.shell) return
      if (buttonCode === Qt.RightButton)
        root.bar.shell.summon(root.moduleName, "{}")
      else
        root.bar.shell.toggle(root.moduleName, "{}")
    }
  }
}
