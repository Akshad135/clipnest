import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// akshad135.clipboard: a clone of omarchy.clipboard. Same history file, capture flow and paste
// scripts; adds pins, category tabs, a per-type preview pane with lazy OCR,
// and a key-hint footer. One box style, one chip style, one pin glyph.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property string category: "all"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property var history: []
  property int pinnedCount: 0

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  property string captureScript: root.pluginDir + "/capture.sh"

  // Shares the [menu] surface tokens — themes that style the menu also style
  // the clipboard.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color lineColor: Util.alpha(foreground, 0.14)
  property color chipBg: Util.alpha(foreground, 0.08)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int boxRadius: Math.max(2, Math.round(Style.cornerRadius * 0.6))
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int searchHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2 + Style.space(8))
  property int tabsHeight: Style.font.caption + Style.spacing.controlPaddingY * 2
  property int footerHeight: Style.font.caption + Style.space(12)
  property int cardWidth: Math.min(Style.space(960), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(44), Style.font.title + Style.spacing.rowPaddingX * 2)
  property int sectionHeight: Style.space(22)
  property int historyLimit: 500

  readonly property var currentRow: displayModel.count > 0 && selectedIndex >= 0 && selectedIndex < displayModel.count ? displayModel.get(selectedIndex) : null
  readonly property bool selectedPinned: root.cursorActive && displayModel.count > 0 && root.selectedIndex < root.pinnedCount

  // OCR: tesseract runs once per image, on first preview, and the result is
  // saved into the entry so it is searchable afterwards.
  property bool ocrAvailable: false
  property string ocrPath: ""

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    root.opened = true
    root.category = "all"
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    filterInput.text = ""
    root.filterText = ""
    root.rebuildDisplay()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function close() {
    root.cancelClearHistory()
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ------------------------------------------------------------ history

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    historyFile.setText(JSON.stringify(root.history.slice(0, root.historyLimit), null, 2) + "\n")
  }

  function addClipboardEntry(entry) {
    var normalized = ClipboardHistory.normalizeEntry(entry)
    if (!normalized) return

    root.history = ClipboardHistory.addEntry(root.history, normalized, root.historyLimit)
    root.saveHistory()
    if (root.opened) root.rebuildDisplay()
  }

  function addClipboardJson(line) {
    root.addClipboardEntry(ClipboardHistory.parseEntryJson(line))
  }

  // One confirm box for the destructive actions: "clear" (Shift+Del),
  // "deletePinned" (Ctrl+Del on a pin), "unpinAll" (Shift+Tab).
  property string confirmAction: ""
  property int confirmHistoryIndex: -1

  function confirmMessage() {
    var t = Commons.I18n.t
    if (root.confirmAction === "deletePinned") return t("clipboard.deletePinned", "Delete this pinned entry?")
    if (root.confirmAction === "unpinAll") return t("clipboard.unpinAll", "Unpin all entries?")
    return t("clipboard.deleteHistory")
  }

  function confirmLabel() {
    var t = Commons.I18n.t
    if (root.confirmAction === "unpinAll") return t("clipboard.unpin", "Unpin")
    return t("common.delete")
  }

  function requestConfirm(action, historyIndex) {
    root.confirmAction = action
    root.confirmHistoryIndex = historyIndex === undefined ? -1 : historyIndex
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    root.requestConfirm("clear")
  }

  function requestDeletePinned(index) {
    var row = root.rowAt(index)
    if (!row || !row.pinned) return
    root.requestConfirm("deletePinned", row.historyIndex)
  }

  function requestUnpinAll() {
    if (root.pinnedCount === 0) return
    root.requestConfirm("unpinAll")
  }

  function cancelClearHistory() {
    root.clearConfirmOpen = false
    root.confirmAction = ""
    root.disarmPointer()
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function confirmClearHistory() {
    var keepIndex = -1
    if (root.confirmAction === "deletePinned") {
      root.history = ClipboardHistory.removeEntryAt(root.history, root.confirmHistoryIndex, true)
      root.selectedIndex = Math.max(0, root.selectedIndex - 1)
    } else if (root.confirmAction === "unpinAll") {
      // Keep the cursor on the same entry after it moves out of the pin section.
      var row = root.currentRow
      keepIndex = row ? row.historyIndex : -1
      root.history = ClipboardHistory.unpinAll(root.history)
    } else {
      root.history = ClipboardHistory.clearHistory(root.history)
      root.selectedIndex = 0
    }
    root.saveHistory()
    root.cursorActive = root.history.length > 0
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.confirmAction = ""
    root.rebuildDisplay()
    if (keepIndex >= 0) root.selectHistoryIndex(keepIndex)
    Qt.callLater(function() { filterInput.forceActiveFocus() })
  }

  function selectHistoryIndex(historyIndex) {
    for (var i = 0; i < displayModel.count; i++) {
      if (displayModel.get(i).historyIndex === historyIndex) {
        root.selectedIndex = i
        return
      }
    }
  }

  function togglePinIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var historyIndex = displayModel.get(index).historyIndex
    root.history = ClipboardHistory.togglePinAt(root.history, historyIndex)
    root.saveHistory()
    root.disarmPointer()
    root.rebuildDisplay()
    root.selectHistoryIndex(historyIndex)
    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.pinned) return // Delete never removes a pin; unpin first (Tab).
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, 50, Commons.I18n.t, Commons.I18n.tn, Commons.I18n.formatNumber, root.category)

    displayModel.clear()
    var pins = 0
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (row.pinned) pins++
      displayModel.append({
        entryType: row.entryType,
        category: row.category,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        path: row.path,
        mime: row.mime,
        pinned: row.pinned,
        section: row.section,
        capturedAt: row.capturedAt,
        ocr: row.ocr,
        truncated: row.truncated,
        historyIndex: row.index
      })
    }
    root.pinnedCount = pins

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  Connections {
    target: Commons.I18n
    function onStringsChanged() { if (root.opened) root.rebuildDisplay() }
  }

  // ------------------------------------------------------------ selection

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setCategory(next) {
    if (next === root.category) return
    root.category = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function cycleCategory(delta) {
    root.setCategory(ClipboardHistory.nextCategory(root.category, delta))
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  // ------------------------------------------------------------ actions

  function rowAt(index) {
    if (index < 0 || index >= displayModel.count) return null
    return displayModel.get(index)
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else if (row.fullText) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  // Links go to the browser, images to the viewer, text to the editor —
  // all via Omarchy's own script.
  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  function copyPlain(text) {
    if (!text) return
    root.opened = false
    Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy', "clipboard-copy", String(text)])
  }

  // Ctrl+Shift+P: the file path behind an image or file entry.
  function copyPathOf(row) {
    if (!row) return
    if (row.entryType === "image") root.copyPlain(row.path)
    else if (row.entryType === "file") root.copyPlain(row.fullText)
  }

  // Ctrl+Shift+C: the entry as plain text — OCR text for images.
  function copyTextOf(row) {
    if (!row) return
    if (row.entryType === "image") root.copyPlain(String(row.ocr || ""))
    else root.copyPlain(row.fullText)
  }

  function hasPath(row) {
    return !!row && (row.entryType === "image" || row.entryType === "file")
  }

  function canOpen(row) {
    return !!row && (row.entryType === "image" || row.entryType === "file" || row.category === "links")
  }

  // Footer hints follow the selected entry's type.
  function footerHints() {
    var row = root.currentRow
    var t = Commons.I18n.t
    var hints = [
      ["↵", t("clipboard.hintPaste", "paste")],
      ["⇧↵", t("clipboard.hintCopy", "copy")]
    ]
    if (root.canOpen(row)) hints.push(["^O", t("clipboard.hintOpen", "open")])
    if (root.hasPath(row)) hints.push(["^⇧P", t("clipboard.hintCopyPath", "copy path")])
    if (row && row.entryType === "image" && row.ocr) hints.push(["^⇧C", t("clipboard.hintCopyText", "copy text")])
    hints.push(["Tab", root.selectedPinned ? t("clipboard.hintUnpin", "unpin") : t("clipboard.hintPin", "pin")])
    if (root.pinnedCount > 0) hints.push(["⇧Tab", t("clipboard.hintUnpinAll", "unpin all")])
    if (row && row.pinned) hints.push(["^Del", t("clipboard.hintDeletePinned", "delete pin")])
    else hints.push(["Del", t("clipboard.hintDelete", "delete")])
    hints.push(["⇧Del", t("clipboard.hintClear", "clear")])
    hints.push(["←→", t("clipboard.hintCategory", "category")])
    hints.push(["^N ^P", t("clipboard.hintMove", "move")])
    return hints
  }

  // ------------------------------------------------------------ OCR

  function maybeStartOcr() {
    if (!root.opened || !root.ocrAvailable || ocrProc.running) return
    var row = root.currentRow
    if (!row || row.entryType !== "image") return
    if (row.ocr !== null && row.ocr !== undefined) return
    root.ocrPath = row.path
    ocrProc.running = true
  }

  function finishOcr(path, text) {
    root.history = ClipboardHistory.setOcrForPath(root.history, path, String(text || "").trim())
    root.saveHistory()
    root.ocrPath = ""
    if (root.opened) {
      var keep = root.selectedIndex
      root.rebuildDisplay()
      root.selectedIndex = Math.min(keep, Math.max(0, displayModel.count - 1))
      Qt.callLater(root.maybeStartOcr)
    }
  }

  onCurrentRowChanged: Qt.callLater(root.maybeStartOcr)
  onOpenedChanged: if (root.opened) Qt.callLater(root.maybeStartOcr)

  Component.onCompleted: initProc.running = true

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
  }

  // Reap watchers left behind by a previous shell instance (ours or the
  // built-in's), then start our own. pdeathsig ties them to the shell.
  Process {
    id: initProc
    command: ["pkill", "-f", "wl-paste .*--watch .*/clipboard/capture\\.sh"]
    onExited: {
      currentProc.running = true
      textWatchProc.running = true
      imageWatchProc.running = true
      ocrCheckProc.running = true
    }
  }

  Process {
    id: ocrCheckProc
    command: ["sh", "-c", "command -v tesseract >/dev/null"]
    onExited: function(code) { root.ocrAvailable = code === 0 }
  }

  Process {
    id: ocrProc
    command: ["timeout", "20s", "tesseract", root.ocrPath, "stdout"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishOcr(root.ocrPath, text)
    }
  }

  Process {
    id: currentProc
    command: [root.captureScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.addClipboardJson(text)
    }
  }

  Process {
    id: textWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "text", "--watch", root.captureScript, "text"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Process {
    id: imageWatchProc
    command: ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", "image/png", "--watch", root.captureScript, "image/png"]
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(data) { root.addClipboardJson(data) }
    }
  }

  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  // ------------------------------------------------------------ reusable looks

  // Every pane is the same box: hairline border, soft fill, shared radius.
  component Box: Rectangle {
    radius: root.boxRadius
    color: Util.alpha(root.foreground, 0.025)
    border.width: Style.normalBorderWidth
    border.color: root.lineColor
  }

  component Chip: Rectangle {
    property string label: ""
    width: chipLabel.implicitWidth + Style.space(10)
    height: chipLabel.implicitHeight + Style.space(4)
    radius: Math.max(2, root.cornerRadius / 3)
    color: root.chipBg

    Text {
      id: chipLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: parent.label
      color: root.foreground
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  function rowIcon(entryType, category) {
    if (entryType === "image") return "󰋩"
    if (entryType === "file") return "󰈔"
    if (category === "links") return "󰌷"
    return "󰈙"
  }

  // ------------------------------------------------------------ window

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-clipboard"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          var ctrl = event.modifiers & Qt.ControlModifier
          var shift = event.modifiers & Qt.ShiftModifier
          var alt = event.modifiers & Qt.AltModifier

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) { filterInput.text = ""; root.setFilter("") }
            else root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_U && event.modifiers === Qt.ControlModifier) {
            filterInput.text = ""
            root.setFilter("")
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (shift) root.requestClearHistory()
            else if (ctrl) root.requestDeletePinned(root.selectedIndex)
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && shift)) {
            root.requestUnpinAll()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            if (root.cursorActive) root.togglePinIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.cycleCategory(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.cycleCategory(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home && ctrl) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End && ctrl) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_O) {
            if (root.cursorActive) root.openSelected(root.rowAt(root.selectedIndex))
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_P) {
            if (root.cursorActive) root.copyPathOf(root.rowAt(root.selectedIndex))
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_C) {
            if (root.cursorActive) root.copyTextOf(root.rowAt(root.selectedIndex))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && alt) root.openSelected(root.rowAt(root.selectedIndex))
            else if (root.cursorActive && shift) root.copySelected(root.rowAt(root.selectedIndex))
            else if (root.cursorActive) root.applySelected(root.rowAt(root.selectedIndex))
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm

          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: root.confirmMessage()
          confirmText: root.confirmLabel()
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ---- search box
        Box {
          width: parent.width
          height: root.searchHeight

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍉"
              color: root.foreground
              opacity: root.filterText ? 0.9 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Item {
              width: parent.width - Style.space(10) * 2 - Style.space(20) - countChip.width
              height: parent.height

              FilterInput {
                id: filterInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                keyHandler: keyCatcher
                readOnly: root.clearConfirmOpen
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                onTextChanged: if (text !== root.filterText) root.setFilter(text)
              }

              Text {
                textFormat: Text.PlainText
                anchors.fill: filterInput
                verticalAlignment: Text.AlignVCenter
                visible: !root.filterText && !filterInput.preeditText
                text: Commons.I18n.t("clipboard.search")
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }
            }

            Chip {
              id: countChip
              anchors.verticalCenter: parent.verticalCenter
              visible: displayModel.count > 0
              label: Commons.I18n.formatNumber(displayModel.count)
            }
          }
        }

        // ---- category tabs
        Row {
          id: categoryRow
          width: parent.width
          height: root.tabsHeight
          spacing: Style.space(18)

          Repeater {
            model: ClipboardHistory.categories

            Item {
              id: tab
              required property string modelData
              readonly property bool active: root.category === modelData

              width: tabLabel.implicitWidth
              height: categoryRow.height

              Text {
                id: tabLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: ClipboardHistory.categoryLabel(tab.modelData, Commons.I18n.t)
                color: tab.active ? root.selectedText : root.foreground
                opacity: tab.active ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: tab.active
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(1, Style.space(2))
                radius: height / 2
                color: root.selectedText
                visible: tab.active
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.setCategory(tab.modelData)
                  filterInput.forceActiveFocus()
                }
              }
            }
          }
        }

        // ---- list + preview
        Item {
          width: parent.width
          height: parent.height - root.searchHeight - root.tabsHeight - root.footerHeight - root.contentSpacing * 3

          Row {
            anchors.fill: parent
            spacing: root.contentSpacing

            Box {
              id: listBox
              width: Math.round(parent.width * 0.44)
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.margins: Style.space(6)
                model: displayModel
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds

                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                  required property string section
                  readonly property bool isPins: section === "pinned"
                  readonly property bool shown: isPins || (root.pinnedCount > 0 && root.pinnedCount < displayModel.count)

                  width: ListView.view.width
                  height: shown ? root.sectionHeight : 0
                  visible: shown

                  Text {
                    visible: parent.isPins
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰐃"
                    color: root.selectedText
                    opacity: 0.8
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Rectangle {
                    visible: !parent.isPins
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.spacing.hairline
                    color: root.lineColor
                  }
                }

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property bool pinned
                  required property string entryType
                  required property string category
                  required property string previewText
                  required property string previewImage

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                  readonly property int thumb: height - Style.space(12)

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.boxRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    // Thumbnail for images, type glyph otherwise: same slot.
                    Item {
                      width: row.thumb
                      height: parent.height

                      Rectangle {
                        visible: row.previewImage.length > 0
                        anchors.centerIn: parent
                        width: row.thumb
                        height: row.thumb
                        radius: Math.max(2, root.boxRadius / 2)
                        color: Util.alpha(root.foreground, 0.05)
                        border.width: Style.normalBorderWidth
                        border.color: root.lineColor
                        clip: true

                        SizedImage {
                          anchors.fill: parent
                          anchors.margins: 1
                          url: row.previewImage
                          crop: true
                          asynchronous: true
                          smooth: true
                        }
                      }

                      Text {
                        visible: row.previewImage.length === 0
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: root.rowIcon(row.entryType, row.category)
                        color: row.hasCursor ? root.selectedText : root.foreground
                        opacity: row.hasCursor ? 0.9 : 0.5
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width - row.thumb - parent.spacing - (pinGlyph.visible ? pinGlyph.width + parent.spacing : 0)
                      height: parent.height
                      text: row.previewText
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      opacity: row.entryType === "image" ? 0.75 : 1.0
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                      id: pinGlyph
                      visible: row.pinned
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: "󰐃"
                      color: root.selectedText
                      opacity: 0.7
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) {
                      root.selectFromPointer(row.index, row, mouse)
                    }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateFromPointer(row.index)
                    }
                  }
                }
              }

              // Empty state
              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(32)
                spacing: Style.space(8)
                visible: displayModel.count === 0

                Text {
                  text: "󰅌"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.history.length === 0 ? Commons.I18n.t("clipboard.empty") : Commons.I18n.t("common.noMatchesFor").arg(root.filterText || ClipboardHistory.categoryLabel(root.category, Commons.I18n.t))
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                  elide: Text.ElideRight
                }
              }
            }

            Box {
              width: parent.width - listBox.width - parent.spacing
              height: parent.height
              clip: true

              PreviewPane {
                anchors.fill: parent
                row: root.currentRow
                ocrBusy: ocrProc.running && root.currentRow && root.ocrPath === root.currentRow.path
                ocrAvailable: root.ocrAvailable
                foreground: root.foreground
                lineColor: root.lineColor
                chipBg: root.chipBg
                selectedText: root.selectedText
                fontFamily: root.fontFamily
                cornerRadius: root.boxRadius
                pad: Style.space(12)
                onOpenLink: root.openSelected(root.currentRow)
                onCopyText: function(text) { root.copyPlain(text) }
              }
            }
          }
        }

        // ---- footer: contextual key hints
        Item {
          width: parent.width
          height: root.footerHeight
          clip: true

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)

            Repeater {
              model: root.footerHints()

              Row {
                required property var modelData
                spacing: Style.space(5)

                Chip {
                  anchors.verticalCenter: parent.verticalCenter
                  label: modelData[0]
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[1]
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }

  // Single click selects; a second click on the selected row pastes.
  property int lastClickedIndex: -1
  function activateFromPointer(index) {
    if (root.lastClickedIndex === index) {
      root.lastClickedIndex = -1
      root.applySelected(root.rowAt(index))
    } else {
      root.lastClickedIndex = index
      clickResetTimer.restart()
    }
  }

  Timer {
    id: clickResetTimer
    interval: 600
    onTriggered: root.lastClickedIndex = -1
  }
}
