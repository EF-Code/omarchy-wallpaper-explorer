import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "WallpaperModel.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool loading: false
  property bool applying: false
  property string view: "themes"
  property string searchText: ""
  property string statusMessage: ""
  property bool statusError: false
  property var themes: []
  property string currentThemeSlug: ""
  property string currentBackgroundPath: ""
  property var selectedTheme: null
  property var selectedBackground: null
  property int themeIndex: 0
  property int backgroundIndex: 0
  property int requestSerial: 0
  property string applyOutput: ""
  property bool applyOutputReady: false
  property int applyExitCode: -1

  readonly property var filteredThemes: Model.filterThemes(root.themes, root.searchText)
  readonly property string pluginId: "io.github.ef-code.wallpaper-explorer"
  readonly property string pluginDirectory: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir) : ""
  readonly property string discoveryScript: root.pluginDirectory + "/discover.sh"
  readonly property string applyScript: root.pluginDirectory + "/apply.sh"

  property color foreground: Color.menu.text
  property color mutedForeground: Qt.alpha(root.foreground, 0.64)
  property color surface: Color.menu.background
  property color surfaceRaised: Qt.alpha(root.foreground, 0.06)
  property color accent: Color.accent
  property color scrim: Qt.rgba(0, 0, 0, 0.78)

  function imageSource(path) {
    return path ? Util.fileUrl(path) : ""
  }

  function displayLabel(path) {
    return Model.labelForPath(path)
  }

  function open(payloadJson) {
    root.opened = true
    root.view = "themes"
    root.searchText = ""
    root.selectedTheme = null
    root.selectedBackground = null
    root.themeIndex = 0
    root.backgroundIndex = 0
    root.statusMessage = ""
    root.statusError = false
    root.refresh()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.applying = false
  }

  function dismiss() {
    if (!root.opened) return
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refresh() {
    if (!root.discoveryScript || root.loading) return

    root.loading = true
    root.statusMessage = "Scanning installed themes…"
    root.statusError = false
    root.requestSerial += 1
    discoveryProc.command = ["bash", root.discoveryScript]
    discoveryProc.running = true
  }

  function loadDiscovery(raw, serial) {
    if (serial !== root.requestSerial) return

    var parsed = Model.parseRows(raw)
    root.themes = parsed.themes
    root.currentThemeSlug = parsed.currentTheme
    root.currentBackgroundPath = parsed.currentBackground
    root.themeIndex = 0
    root.backgroundIndex = 0
    root.selectedTheme = null
    root.selectedBackground = null
    root.statusMessage = ""
    root.statusError = false
    Qt.callLater(function() {
      if (root.opened && root.view === "themes" && root.filteredThemes.length > 0)
        themeGrid.positionViewAtIndex(0, GridView.Beginning)
    })
  }

  function openTheme(theme) {
    if (!theme) return

    root.selectedTheme = theme
    root.view = "backgrounds"
    root.searchText = ""
    root.backgroundIndex = Model.indexOfPath(theme.backgrounds, root.currentBackgroundPath)
    if (root.backgroundIndex < 0) root.backgroundIndex = 0
    root.selectedBackground = theme.backgrounds.length > 0
      ? theme.backgrounds[root.backgroundIndex] : null
    Qt.callLater(function() { backgroundGrid.forceActiveFocus() })
  }

  function backToThemes() {
    root.view = "themes"
    root.searchText = ""
    root.selectedTheme = null
    root.selectedBackground = null
    root.themeIndex = 0
    Qt.callLater(function() { themeGrid.forceActiveFocus() })
  }

  function setThemeIndex(index) {
    var count = root.filteredThemes.length
    if (count === 0) {
      root.themeIndex = 0
      return
    }
    root.themeIndex = Math.max(0, Math.min(index, count - 1))
    themeGrid.positionViewAtIndex(root.themeIndex, GridView.Contain)
  }

  function setBackgroundIndex(index) {
    if (!root.selectedTheme || root.selectedTheme.backgrounds.length === 0) {
      root.backgroundIndex = 0
      root.selectedBackground = null
      return
    }
    var count = root.selectedTheme.backgrounds.length
    root.backgroundIndex = Math.max(0, Math.min(index, count - 1))
    root.selectedBackground = root.selectedTheme.backgrounds[root.backgroundIndex]
    backgroundGrid.positionViewAtIndex(root.backgroundIndex, GridView.Contain)
  }

  function moveSelection(dx, dy) {
    if (root.view === "themes") {
      var themeCount = root.filteredThemes.length
      if (themeCount === 0) return
      var themeColumns = Model.gridColumns(themeGrid.width, Style.space(250), 4)
      var nextTheme = root.themeIndex + (dy !== 0 ? dy * themeColumns : dx)
      root.setThemeIndex((nextTheme + themeCount) % themeCount)
      return
    }

    if (!root.selectedTheme || root.selectedTheme.backgrounds.length === 0) return
    var backgroundCount = root.selectedTheme.backgrounds.length
    var backgroundColumns = Model.gridColumns(backgroundGrid.width, Style.space(250), 4)
    var nextBackground = root.backgroundIndex + (dy !== 0 ? dy * backgroundColumns : dx)
    root.setBackgroundIndex((nextBackground + backgroundCount) % backgroundCount)
  }

  function activateSelection() {
    if (root.view === "themes") {
      if (root.filteredThemes.length > 0) root.openTheme(root.filteredThemes[root.themeIndex])
      return
    }
    root.applySelected()
  }

  function applySelected() {
    if (!root.selectedTheme || !root.selectedBackground || root.applying) return

    root.applying = true
    root.statusMessage = "Applying wallpaper…"
    root.statusError = false
    root.applyOutput = ""
    root.applyOutputReady = false
    root.applyExitCode = -1
    applyProc.command = ["bash", root.applyScript,
      root.selectedBackground.path, root.selectedTheme.slug]
    applyProc.running = true
  }

  function finishApply(raw, exitCode) {
    root.applying = false
    if (exitCode !== 0) {
      root.statusError = true
      root.statusMessage = "Wallpaper could not be applied."
      return
    }

    var appliedPath = ""
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields[0] === "applied") appliedPath = fields.slice(1).join("\t")
    }
    if (appliedPath) root.currentBackgroundPath = appliedPath
    root.statusError = false
    root.statusMessage = "Applied from " + root.selectedTheme.name
    successTimer.restart()
  }

  function finishApplyWhenReady() {
    if (root.applyExitCode < 0 || !root.applyOutputReady) return
    var exitCode = root.applyExitCode
    var output = root.applyOutput
    root.applyExitCode = -1
    root.applyOutputReady = false
    root.finishApply(output, exitCode)
  }

  function handleKey(event) {
    if (searchField.activeFocus) {
      if (event.key === Qt.Key_Escape) {
        searchField.clear()
        focusScope.forceActiveFocus()
        event.accepted = true
      }
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (root.view === "backgrounds") root.backToThemes()
      else root.dismiss()
      event.accepted = true
    } else if (event.key === Qt.Key_Left) {
      root.moveSelection(-1, 0)
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      root.moveSelection(1, 0)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.moveSelection(0, -1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.moveSelection(0, 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activateSelection()
      event.accepted = true
    } else if (event.key === Qt.Key_R) {
      root.refresh()
      event.accepted = true
    }
  }

  onOpenedChanged: {
    if (opened) Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  Process {
    id: discoveryProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadDiscovery(text, root.requestSerial)
    }
    stderr: StdioCollector { id: discoveryStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0) {
        root.statusError = true
        root.statusMessage = "Could not scan installed themes."
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyOutput = String(text || "")
        root.applyOutputReady = true
        root.finishApplyWhenReady()
      }
    }
    stderr: StdioCollector { id: applyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.applyExitCode = exitCode
      root.finishApplyWhenReady()
    }
  }

  Timer {
    id: successTimer
    interval: 900
    repeat: false
    onTriggered: root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "wallpaper-explorer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(48), Style.space(1160))
        height: Math.min(parent.height - Style.space(48), Style.space(760))
        color: root.surface
        radius: Style.space(18)
        border.width: 1
        border.color: Qt.alpha(root.foreground, 0.14)
        clip: true

        MouseArea {
          anchors.fill: parent
          onClicked: mouse.accepted = true
        }

        FocusScope {
          id: focusScope
          anchors.fill: parent
          anchors.margins: Style.space(22)
          focus: root.opened
          Keys.priority: Keys.AfterItem
          Keys.onPressed: function(event) { root.handleKey(event) }

          ColumnLayout {
            anchors.fill: parent
            spacing: Style.space(12)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)

              Button {
                visible: root.view === "backgrounds"
                text: "‹ Themes"
                focusable: true
                onClicked: root.backToThemes()
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  Layout.fillWidth: true
                  text: root.view === "themes" ? "Wallpaper Explorer" : root.selectedTheme.name
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  text: root.view === "themes"
                    ? "Choose a wallpaper from any installed Omarchy theme"
                    : root.selectedTheme.count + " wallpapers · theme colors stay unchanged"
                  color: root.mutedForeground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                text: "Refresh"
                focusable: true
                enabled: !root.loading && !root.applying
                onClicked: root.refresh()
              }

              Button {
                text: "Close"
                focusable: true
                onClicked: root.dismiss()
              }
            }

            TextField {
              id: searchField
              visible: root.view === "themes"
              Layout.fillWidth: true
              placeholderText: "Search installed themes…"
              text: root.searchText
              activeFocusOnTab: true
              onTextChanged: {
                root.searchText = text
                root.themeIndex = 0
                Qt.callLater(function() {
                  if (root.filteredThemes.length > 0)
                    themeGrid.positionViewAtIndex(0, GridView.Beginning)
                })
              }
            }

            Text {
              visible: root.view === "themes" && root.currentThemeSlug !== ""
              Layout.fillWidth: true
              text: "Current theme: " + Model.titleForSlug(root.currentThemeSlug)
              color: root.mutedForeground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            StackLayout {
              id: pages
              Layout.fillWidth: true
              Layout.fillHeight: true
              currentIndex: root.view === "themes" ? 0 : 1

              Item {
                GridView {
                  id: themeGrid
                  anchors.fill: parent
                  clip: true
                  focus: root.opened && root.view === "themes"
                  model: root.filteredThemes
                  readonly property int columns: Model.gridColumns(width, Style.space(250), 4)
                  cellWidth: width / columns
                  cellHeight: Style.space(190)

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: themeGrid.cellWidth
                    height: themeGrid.cellHeight

                    Rectangle {
                      id: themeCard
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      radius: Style.space(12)
                      color: root.themeIndex === index
                        ? Qt.alpha(root.accent, 0.18) : root.surfaceRaised
                      border.width: root.themeIndex === index ? 2 : 1
                      border.color: root.themeIndex === index
                        ? root.accent : Qt.alpha(root.foreground, 0.10)
                      clip: true

                      Image {
                        id: themePreview
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Style.space(126)
                        source: root.imageSource(modelData.preview)
                        sourceSize.width: 640
                        sourceSize.height: 360
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        visible: status === Image.Ready
                      }

                      Rectangle {
                        anchors.fill: themePreview
                        visible: !themePreview.visible
                        color: Qt.alpha(root.accent, 0.12)
                        Text {
                          anchors.centerIn: parent
                          text: modelData.count > 0 && modelData.preview
                            ? "Loading preview…" : "No preview"
                          color: root.mutedForeground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Style.space(64)
                        color: Qt.alpha(root.surface, 0.96)

                        ColumnLayout {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(12)
                          anchors.rightMargin: Style.space(12)
                          anchors.topMargin: Style.space(8)
                          anchors.bottomMargin: Style.space(8)
                          spacing: 0

                          Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                            elide: Text.ElideRight
                          }

                          Text {
                            Layout.fillWidth: true
                            text: modelData.count === 1
                              ? "1 wallpaper" : modelData.count + " wallpapers"
                            color: root.mutedForeground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                          }
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.themeIndex = index
                        onClicked: {
                          root.themeIndex = index
                          root.openTheme(modelData)
                        }
                      }
                    }
                  }

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(6)
                    visible: root.loading || root.filteredThemes.length === 0

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.loading ? "Scanning installed themes…" : "No matching themes"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: root.loading ? "" : "Try a different search term."
                      color: root.mutedForeground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }

              Item {
                GridView {
                  id: backgroundGrid
                  anchors.fill: parent
                  clip: true
                  focus: root.opened && root.view === "backgrounds"
                  model: root.selectedTheme ? root.selectedTheme.backgrounds : []
                  readonly property int columns: Model.gridColumns(width, Style.space(250), 4)
                  cellWidth: width / columns
                  cellHeight: Style.space(190)

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: backgroundGrid.cellWidth
                    height: backgroundGrid.cellHeight

                    Rectangle {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      radius: Style.space(12)
                      color: root.backgroundIndex === index
                        ? Qt.alpha(root.accent, 0.18) : root.surfaceRaised
                      border.width: root.backgroundIndex === index ? 2 : 1
                      border.color: root.backgroundIndex === index
                        ? root.accent : Qt.alpha(root.foreground, 0.10)
                      clip: true

                      Image {
                        id: backgroundPreview
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: Style.space(142)
                        source: root.imageSource(modelData.thumbnail)
                        sourceSize.width: 640
                        sourceSize.height: 360
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Style.space(38)
                        color: Qt.alpha(root.surface, 0.96)
                        Text {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(12)
                          anchors.rightMargin: Style.space(12)
                          verticalAlignment: Text.AlignVCenter
                          text: root.displayLabel(modelData.path)
                          color: root.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.setBackgroundIndex(index)
                        onClicked: root.setBackgroundIndex(index)
                      }
                    }
                  }

                  Column {
                    anchors.centerIn: parent
                    spacing: Style.space(6)
                    visible: !root.loading && (!root.selectedTheme || root.selectedTheme.backgrounds.length === 0)

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "No wallpapers in this theme"
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Choose another theme to continue."
                      color: root.mutedForeground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              Text {
                Layout.fillWidth: true
                visible: root.statusMessage !== ""
                text: root.statusMessage
                color: root.statusError ? Color.urgent : root.mutedForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }

              Text {
                visible: root.statusMessage === ""
                text: root.view === "themes" ? "Enter to browse · Esc to close" : "Enter to apply · Esc to go back"
                color: root.mutedForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Button {
                visible: root.view === "backgrounds"
                text: root.applying ? "Applying…" : "Apply wallpaper"
                focusable: true
                enabled: !!root.selectedBackground && !root.applying
                onClicked: root.applySelected()
              }
            }
          }
        }
      }
    }
  }
}
