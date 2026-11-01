import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import "ImagePickerModel.js" as ImagePickerModel

Item {
  id: root

  // Injected by omarchy-shell; defaults to the session OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string stateHome: Quickshell.env("HOME") + "/.local/state"
  property string imageDirs: Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIRS") || Quickshell.env("OMARCHY_IMAGE_SELECTOR_DIR") || Quickshell.env("OMARCHY_STOCK_BACKGROUNDS_DIR") || (stateHome + "/omarchy/current/theme/backgrounds")
  property string imageRows: ""
  property string loadedImageRows: ""
  property string selectionFile: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTION_FILE") || Quickshell.env("OMARCHY_BACKGROUND_SELECTION_FILE")
  property string selectedImage: Quickshell.env("OMARCHY_IMAGE_SELECTOR_SELECTED")
  property int selectedIndex: 0
  property bool imagesLoaded: false
  property bool opened: false
  property bool showLabels: false
  property bool filterable: false
  property bool layoutSettled: false
  property bool requestActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property string doneFile: ""
  property string filterText: ""
  property var doneFilesToRelease: []
  property int rowLoadCount: 0
  property double openStartedAt: 0
  // `{"source":"themes"}` summons (the theme menu, Super+Ctrl+T) build the
  // theme rows here instead of passing them in, and apply via theme-set.
  property string themeRows: ""
  property bool themeMode: false
  property bool themeOpenPending: false
  // The stock theme switcher supplies preview-cache paths. Other image
  // picker clients (wallpapers, screenshots, etc.) retain the original UI.
  readonly property bool themeCollections: showLabels && imageArray.length > 0
    && imageArray.every(function(image) { return image.filePath.indexOf('/omarchy/theme-selector/previews/') !== -1 })
  // Bound to the central [image-picker] section in shell.toml via Color.qml.
  // `dimColor` tints unselected slices and text outlines on top of the scrim;
  // it intentionally tracks the foundational background, not a surface role.
  property color dimColor: Color.background
  property color foreground: Color.imagePicker.text
  // Newer shells dropped `imagePicker.scrim` (the stock picker draws no
  // backdrop); binding it directly assigns undefined to a color.
  property color scrim: Color.imagePicker.scrim || "transparent"
  property color selectedBorder: Color.imagePicker.selectedBorder
  property color unselectedBorder: Color.imagePicker.unselectedBorder
  property int expandedWidth: 768
  property int expandedHeight: 475
  property int sliceWidth: 108
  property int sliceHeight: 432
  property int sliceSpacing: -30
  property int skewOffset: 28
  property int bottomChromeHeight: showLabels ? (filterable ? 104 : 74) : (filterable ? 60 : 30)

  readonly property string pluginId: "io.github.ejuro.extended-theme-picker"
  readonly property var settings: ImagePickerModel.settingsFromShellJson(shellConfig.text(), pluginId)
  readonly property bool swapAnimation: settings.cardSwapAnimation
  readonly property bool glassOverlay: settings.glassOverlay
  property bool filtering: false

  FileView {
    id: shellConfig
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  // Hyprland applies layer rules when a surface maps, so the rule has to exist
  // before the first open. It only blurs when Hyprland blur itself is enabled
  // (Omarchy's Glassy toggle); otherwise the glass is tint and sheen alone.
  onGlassOverlayChanged: if (glassOverlay) Util.execArgv(["hyprctl", "eval", 'hl.layer_rule({ match = { namespace = "^omarchy-image-selector$" }, blur = true, ignore_alpha = 0.35 })'])

  onOpenedChanged: if (!opened) layoutSettled = false

  function scriptPath(name) {
    return omarchyPath + "/shell/plugins/image-picker/" + name
  }

  function focusPicker() {
    if (root.opened && root.imagesLoaded && root.layoutSettled) {
      if (root.themeCollections && collectionsLoader.item) collectionsLoader.item.focusPicker()
      else carousel.forceActiveFocus()
    }
  }

  function revealWhenSettled(serial) {
    Qt.callLater(function() {
      if (serial === root.requestSerial && root.opened && root.imagesLoaded && root.imageArray.length > 0) {
        root.layoutSettled = true
        root.focusPicker()
      }
    })
  }

  function currentPath() {
    if (imageArray.length === 0 || !itemMatches(selectedIndex)) return ""
    return imageArray[selectedIndex].filePath
  }

  function collectionStatus() {
    var view = collectionsLoader.item
    return JSON.stringify({ opened: opened, collections: themeCollections, count: imageArray.length,
      ready: view ? view.ready : false, error: view ? view.errorText : '',
      group: view ? view.collectionId : '', selected: view && view.theme ? view.theme.fileName : '',
      layout: view && view.gridMode ? 'grid' : 'cards',
      query: view ? view.query : '', dialog: view ? view.dialog : '',
      removalMenuAvailable: view ? typeof view.selectRemoval === 'function' : false,
      activeTheme: view ? view.activeSlug : '',
      preferredCollection: view ? view.preferredCollection : '',
      rendering: view ? view.renderingStats() : {},
      rowLoads: rowLoadCount, openAgeMs: Date.now() - openStartedAt,
      focused: view ? view.activeFocus : false })
  }

  function nameForPath(path) {
    return ImagePickerModel.nameForPath(path)
  }

  function labelForPath(path) {
    return ImagePickerModel.labelForPath(path)
  }

  function currentLabel() {
    var path = currentPath()
    if (!path) return filterText ? "No matches" : ""

    return labelForPath(path)
  }

  function itemMatches(index) {
    return ImagePickerModel.itemMatches(imageArray, index, filterText)
  }

  function firstMatchingIndex() {
    return ImagePickerModel.firstMatchingIndex(imageArray, filterText)
  }

  function filteredPosition(index) {
    return ImagePickerModel.filteredPosition(imageArray, index, filterText)
  }

  function selectedFilteredPosition() {
    return ImagePickerModel.selectedFilteredPosition(imageArray, selectedIndex, filterText)
  }

  function select(index, immediate) {
    if (imageArray.length === 0) return
    if (index < 0) index = 0
    else if (index >= imageArray.length) index = imageArray.length - 1
    if (!itemMatches(index)) return
    if (index === selectedIndex && immediate !== true) return

    selectedIndex = index
  }

  function selectAdjacent(direction) {
    var count = imageArray.length
    if (count === 0) return

    var index = selectedIndex
    for (var i = 0; i < count; i++) {
      index = (index + direction + count) % count
      if (itemMatches(index)) {
        select(index)
        return
      }
    }
  }

  function updateFilter(nextFilterText) {
    filtering = true
    filterText = nextFilterText

    if (!itemMatches(selectedIndex)) {
      var first = ImagePickerModel.nextSelectedIndexForFilter(imageArray, selectedIndex, filterText)
      if (first >= 0) selectedIndex = first
    }
    filtering = false
  }

  function releaseNextDoneFile() {
    if (releaseProc.running || doneFilesToRelease.length === 0) return

    var path = doneFilesToRelease.shift()
    releaseProc.command = ["bash", "-c", ": > " + Util.shellQuote(path)]
    releaseProc.running = true
  }

  function finishDoneFile(path) {
    if (!path) return
    doneFilesToRelease.push(path)
    releaseNextDoneFile()
  }

  function applySelected() {
    var path = currentPath()

    if (themeMode) {
      themeMode = false
      root.opened = false
      if (path) Util.execArgv(["omarchy-theme-set", ImagePickerModel.nameForPath(path)])
      return
    }

    if (!path || !selectionFile) {
      cancel()
      return
    }

    var activeSelectionFile = selectionFile
    var activeDoneFile = doneFile
    applySerial = requestSerial
    requestActive = false
    selectionFile = ""
    doneFile = ""

    applyProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(path) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    applyProc.running = true
  }

  function cancel() {
    themeMode = false
    themeOpenPending = false

    if (requestActive)
      finishDoneFile(doneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    root.opened = false
  }

  function closeSelector(nextDoneFile) {
    requestSerial += 1
    themeMode = false
    themeOpenPending = false

    if (requestActive)
      finishDoneFile(doneFile)

    if (nextDoneFile && nextDoneFile !== doneFile)
      finishDoneFile(nextDoneFile)

    requestActive = false
    selectionFile = ""
    doneFile = ""
    filterText = ""
    root.opened = false
  }

  function loadRows(rows, reveal) {
    rowLoadCount++
    var newImages = ImagePickerModel.loadRows(rows)

    root.loadedImageRows = rows
    root.selectedIndex = root.indexForSelectedImage(newImages)
    root.imageArray = newImages
    root.imagesLoaded = true

    if (reveal !== false) {
      root.opened = true
      root.revealWhenSettled(root.requestSerial)
    }
  }

  function openSelector(nextImageDirs, nextImageRows, nextSelectedImage, nextSelectionFile, nextDoneFile, nextShowLabels, nextFilterable) {
    openStartedAt = Date.now()
    if (requestActive && doneFile && doneFile !== nextDoneFile)
      finishDoneFile(doneFile)

    requestSerial += 1
    themeMode = false
    themeOpenPending = false

    imageDirs = nextImageDirs
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    selectionFile = nextSelectionFile
    doneFile = nextDoneFile
    requestActive = !!doneFile
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      root.select(root.selectedImageIndex(), true)
      imagesLoaded = true
      opened = true
      root.revealWhenSettled(requestSerial)
      return
    }

    if (imageRows) {
      var rowsToLoad = imageRows
      var rowsSerial = requestSerial
      imageArray = []
      selectedIndex = 0
      imagesLoaded = true
      opened = true
      Qt.callLater(function() {
        if (rowsSerial === root.requestSerial)
          root.loadRows(rowsToLoad, true)
      })
      return
    }

    imageArray = []
    selectedIndex = 0
    imagesLoaded = false
    opened = false
    startImageScan(requestSerial, imageDirs)
  }

  property var imageArray: []

  function startImageScan(serial, dirs) {
    if (loadImagesProc.running) {
      loadImagesProc.queuedSerial = serial
      loadImagesProc.queuedDirs = dirs
      return
    }

    loadImagesProc.activeSerial = serial
    loadImagesProc.queuedSerial = 0
    loadImagesProc.queuedDirs = ""
    loadImagesProc.command = [root.scriptPath("list.sh"), dirs]
    loadImagesProc.running = true
  }

  function indexForSelectedImage(images) {
    return ImagePickerModel.indexForSelectedImage(images, selectedImage)
  }

  function selectedImageIndex() {
    return indexForSelectedImage(imageArray)
  }

  Process {
    id: loadImagesProc
    property int activeSerial: 0
    property int queuedSerial: 0
    property string queuedDirs: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (loadImagesProc.activeSerial === root.requestSerial)
          root.loadRows(String(text || ""), true)
      }
    }
    onExited: {
      var serial = queuedSerial
      var dirs = queuedDirs
      activeSerial = 0
      queuedSerial = 0
      queuedDirs = ""
      if (serial > 0 && serial === root.requestSerial)
        root.startImageScan(serial, dirs)
    }
  }

  // Lifecycle hooks invoked by omarchy-shell summon/hide. shell.summon(id,
  // payloadJson) hands the JSON to open() here; shell.hide(id) calls close().
  // The shell host owns the stable `image-selector` IPC target and forwards
  // those lower-level positional calls here.
  function open(payload) {
    var args = {}
    if (payload) {
      try { args = JSON.parse(payload) || {} } catch (e) { args = {} }
    }
    if (args.source === "themes") {
      openThemes()
      return
    }
    var dirs = String(args.imageDirs || imageDirs)
    var rows = String(args.imageRows || "")
    var sel = String(args.selectedImage || selectedImage)
    var selFile = String(args.selectionFile || "")
    var doneF = String(args.doneFile || "")
    var labels = args.showLabels === true || args.showLabels === "true"
    var filter = args.filterable === true || args.filterable === "true"
    openSelector(dirs, rows, sel, selFile, doneF, labels, filter)
  }

  function close() {
    cancel()
  }

  function preloadRows(nextImageRows, nextSelectedImage, nextShowLabels, nextFilterable) {
    // Theme/background set hooks can warm selector rows after a picker was
    // dismissed. Ignore those preloads while a user-visible request is open;
    // otherwise the preload resets layoutSettled without revealing again,
    // leaving only the fullscreen scrim.
    if (opened || requestActive) return

    requestSerial += 1
    imageRows = nextImageRows
    selectedImage = nextSelectedImage
    showLabels = nextShowLabels === true || nextShowLabels === "true"
    filterable = nextFilterable === true || nextFilterable === "true"
    filterText = ""
    layoutSettled = false

    if (imageRows && imageRows === loadedImageRows && imageArray.length > 0) {
      selectedIndex = selectedImageIndex()
      imagesLoaded = true
    } else if (imageRows) {
      loadRows(imageRows, false)
    }
  }

  function currentThemePreview() {
    var name = String(themeNameFile.text() || "").trim()
    var images = ImagePickerModel.loadRows(themeRows)
    for (var i = 0; i < images.length; i++) {
      if (ImagePickerModel.nameForPath(images[i].filePath) === name) return images[i].filePath
    }
    return ""
  }

  // Opens from the rows cached at startup, then refreshes them; only the
  // first open before that startup read lands waits on the script.
  function openThemes() {
    if (themeRows) openThemeRows()
    else themeOpenPending = true
    refreshThemeRows()
  }

  function openThemeRows() {
    openSelector("", themeRows, currentThemePreview(), "", "", true, true)
    themeMode = true
  }

  function refreshThemeRows() {
    if (themeRowsProc.running) { themeRowsProc.queued = true; return }
    themeRowsProc.running = true
  }

  function updateThemeRows(rows) {
    var changed = rows !== themeRows
    themeRows = rows

    if (themeOpenPending) {
      themeOpenPending = false
      if (rows) openThemeRows()
    } else if (changed && rows && themeMode && opened) {
      selectedImage = currentPath() || currentThemePreview()
      imageRows = rows
      loadRows(rows, false)
    }
  }

  Component.onCompleted: refreshThemeRows()

  FileView {
    id: themeNameFile
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    onFileChanged: reload()
  }

  Process {
    id: themeRowsProc
    property bool queued: false
    command: [root.omarchyPath + "/bin/omarchy-theme-switcher", "--print-rows"]
    stdout: StdioCollector {
      onStreamFinished: root.updateThemeRows(String(text || "").trim())
    }
    onExited: {
      if (queued) {
        queued = false
        running = true
      }
    }
  }

  Process {
    id: applyProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Process {
    id: releaseProc
    onExited: root.releaseNextDoneFile()
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-image-selector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      visible: root.opened && root.imagesLoaded
      color: root.glassOverlay ? Util.alpha(Color.background, 0.5)
        : root.themeCollections ? Util.alpha(Color.background, 0.84) : root.scrim

      Rectangle {
        visible: root.glassOverlay
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.4
        gradient: Gradient {
          GradientStop { position: 0; color: Util.alpha(Color.foreground, 0.06) }
          GradientStop { position: 1; color: "transparent" }
        }
      }

      Rectangle {
        visible: root.glassOverlay
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: Util.alpha(Color.foreground, 0.08)
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened && root.imagesLoaded
      onClicked: root.cancel()
    }

    Item {
      id: card
      visible: !root.themeCollections && root.opened && root.imagesLoaded && root.layoutSettled && root.imageArray.length > 0
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.expandedHeight + Style.space(30) + root.bottomChromeHeight
      anchors.centerIn: parent

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
          id: carousel
          anchors.top: parent.top
          anchors.topMargin: Style.space(30)
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.bottomChromeHeight
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
          clip: false
          focus: true

          readonly property real itemStep: root.sliceWidth + root.sliceSpacing
          readonly property real previewX: (width - root.expandedWidth) / 2

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              if (root.filterText) {
                root.updateFilter("")
              } else {
                root.cancel()
              }
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.applySelected()
              event.accepted = true
            } else if (root.filterable && Util.editsFilter(event, root.filterText)) {
              root.updateFilter(Util.editedFilter(event, root.filterText))
              event.accepted = true
            } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab) {
              root.selectAdjacent(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
              root.selectAdjacent(1)
              event.accepted = true
            } else if (root.filterable && event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
              root.updateFilter(root.filterText + event.text)
              event.accepted = true
            }
          }

          Component.onCompleted: forceActiveFocus()

          Repeater {
            // The collection picker replaces this carousel entirely. Hidden
            // delegates still instantiate effects and synchronously load images.
            model: root.themeCollections ? 0 : root.imageArray.length

            delegate: Item {
              id: item
              required property int index

              readonly property var imageData: root.imageArray[index]
              readonly property string filePath: imageData ? imageData.filePath : ""
              readonly property string fileName: imageData ? imageData.fileName : ""
              readonly property string thumbnailPath: imageData ? imageData.thumbnailPath : ""

              readonly property bool matched: root.itemMatches(index)
              readonly property int relativeIndex: root.filteredPosition(index) - root.selectedFilteredPosition()
              readonly property bool selected: matched && index === root.selectedIndex
              readonly property bool nearby: matched && Math.abs(relativeIndex) <= 16
              property bool sourceActivated: nearby
              onNearbyChanged: if (nearby) sourceActivated = true

              property real shownOffset: 0
              Component.onCompleted: shownOffset = relativeIndex
              readonly property var layout: ImagePickerModel.cardLayout(shownOffset, {
                previewX: carousel.previewX, previewWidth: root.expandedWidth, previewHeight: root.expandedHeight,
                sliceWidth: root.sliceWidth, sliceHeight: root.sliceHeight, step: carousel.itemStep,
                firstRightX: carousel.previewX + root.expandedWidth + root.sliceSpacing })

              NumberAnimation { id: swap; target: item; property: "shownOffset"; duration: 220; easing.type: Easing.OutCubic }

              onRelativeIndexChanged: {
                swap.stop()
                if (root.swapAnimation && root.layoutSettled && !root.filtering && matched
                    && Math.abs(shownOffset) <= 16 && Math.abs(relativeIndex - shownOffset) <= 3) {
                  swap.to = relativeIndex
                  swap.start()
                } else {
                  shownOffset = relativeIndex
                }
              }

              visible: nearby
              x: layout.x
              width: layout.width
              height: layout.height
              y: layout.y
              z: (selected ? 101 : 0) + 100 - Math.min(Math.abs(shownOffset), 40) * 2

              readonly property real skAbs: Math.abs(root.skewOffset)
              readonly property real topLeft: root.skewOffset >= 0 ? skAbs : 0
              readonly property real topRight: root.skewOffset >= 0 ? width : width - skAbs
              readonly property real bottomRight: root.skewOffset >= 0 ? width - skAbs : width
              readonly property real bottomLeft: root.skewOffset >= 0 ? 0 : skAbs

              Item {
                id: maskShape
                anchors.fill: parent
                visible: false
                layer.enabled: true

                Shape {
                  anchors.fill: parent
                  antialiasing: true
                  preferredRendererType: Shape.CurveRenderer
                  ShapePath {
                    fillColor: "white"
                    strokeColor: "transparent"
                    startX: item.topLeft; startY: 0
                    PathLine { x: item.topRight; y: 0 }
                    PathLine { x: item.bottomRight; y: item.height }
                    PathLine { x: item.bottomLeft; y: item.height }
                    PathLine { x: item.topLeft; y: 0 }
                  }
                }
              }

              Item {
                anchors.fill: parent
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                  maskEnabled: true
                  maskSource: maskShape
                  maskThresholdMin: 0.3
                  maskSpreadAtMin: 0.3
                }

                Image {
                  id: image
                  anchors.fill: parent
                  // Load only the initial/visited nearby images, but keep the
                  // source once activated so Qt does not tear textures down as
                  // selection moves through the carousel.
                  source: item.sourceActivated && item.thumbnailPath ? Util.fileUrl(item.thumbnailPath) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: false
                  cache: true
                  smooth: true
                }

                Rectangle {
                  anchors.fill: parent
                  color: Util.alpha(root.dimColor, 0.42 * (1 - item.layout.emphasis))
                }
              }

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "transparent"
                  strokeColor: item.selected ? root.selectedBorder : root.unselectedBorder
                  strokeWidth: item.selected ? 1.5 : 1
                  joinStyle: ShapePath.MiterJoin
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: item.selected ? root.applySelected() : root.select(index)
              }
            }
          }
        }

        Text {
          id: selectedLabel
          textFormat: Text.PlainText
          visible: root.showLabels
          anchors.top: carousel.bottom
          anchors.topMargin: Style.space(16)
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.currentLabel()
          color: root.foreground
          style: Text.Outline
          styleColor: Util.alpha(root.dimColor, 0.7)
          font.pixelSize: Style.font.display
          font.weight: Font.DemiBold
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: root.filterable && root.filterText
          anchors.top: selectedLabel.bottom
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: carousel.horizontalCenter
          width: root.expandedWidth
          text: root.filterText
          color: root.foreground
          opacity: 0.85
          style: Text.Outline
          styleColor: Util.alpha(root.dimColor, 0.7)
          font.pixelSize: Style.font.title
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
    }

    Loader {
      id: collectionsLoader
      anchors.fill: parent
      active: root.themeCollections
      visible: active && root.opened && root.layoutSettled
      sourceComponent: ThemeCollections {
        allowUninstall: true
        swapAnimation: root.swapAnimation
        images: root.imageArray
        currentImage: root.selectedImage
        presented: root.opened && root.layoutSettled
        onApplyRequested: function(path) {
          root.select(ImagePickerModel.indexForSelectedImage(root.imageArray, path), true)
          root.applySelected()
        }
        onCancelRequested: root.cancel()
        onThemeRemoved: function(slug) {
          root.imageArray = root.imageArray.filter(function(image) {
            return image.fileName.replace(/\.[^.]+$/, '') !== slug
          })
        }
      }
    }
  }
}
