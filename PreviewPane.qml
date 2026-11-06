import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// Per-type preview for the selected row: a header with the type and metadata
// chips, then the content (framed image, wrapped text, link, or file list),
// then OCR text for images once it has been read.
Item {
  id: root

  // Row from the picker's display model, or null.
  property var row: null
  property bool ocrBusy: false
  property bool ocrAvailable: true
  // "WxH" for the current image, probed by the picker; "" until known.
  property string imageDims: ""

  property color foreground: "white"
  property color lineColor: "gray"
  property color chipBg: "gray"
  property color selectedText: "white"
  property string fontFamily: ""
  property int cornerRadius: 0
  property int pad: 12

  signal openLink()
  signal copyText(string text)

  readonly property string entryType: row ? String(row.entryType) : ""
  readonly property string category: row ? String(row.category) : ""
  readonly property string fullText: row ? String(row.fullText) : ""
  readonly property string imageUrl: row ? String(row.previewImage) : ""
  readonly property bool isImage: entryType === "image"
  readonly property bool isFile: entryType === "file"
  readonly property bool isLink: category === "links"
  readonly property var filePathList: isFile ? fullText.split("\n") : []
  readonly property string ocrText: row && row.ocr !== null && row.ocr !== undefined ? String(row.ocr) : ""
  readonly property bool hasOcr: isImage && ocrText.trim().length > 0

  function typeIcon() {
    if (isImage) return "󰋩"
    if (isFile) return "󰈔"
    if (isLink) return "󰌷"
    return "󰈙"
  }

  function typeLabel() {
    if (isImage) return Commons.I18n.t("clipboard.typeImage", "Image")
    if (isFile) return filePathList.length === 1
      ? Commons.I18n.t("clipboard.typeFile", "File")
      : Commons.I18n.t("clipboard.typeFiles", "Files")
    if (isLink) return Commons.I18n.t("clipboard.typeLink", "Link")
    return Commons.I18n.t("clipboard.typeText", "Text")
  }

  // Catalog plural when the key exists, English otherwise.
  function plural(key, count, one, other) {
    var value = Commons.I18n.tn(key, count, "")
    if (typeof value !== "string" || !value) value = count === 1 ? one : other
    return value.replace("%1", Commons.I18n.formatNumber(count))
  }

  function chips() {
    if (!row) return []
    var out = []
    if (isImage) {
      if (root.imageDims) out.push(root.imageDims)
      out.push(String(row.mime || "").replace(/^image\//, ""))
      if (row.capturedAt) out.push(String(row.capturedAt))
      if (hasOcr) out.push(Commons.I18n.t("clipboard.chipOcr", "%1 words of text").replace("%1", ClipboardHistory.textStats(ocrText).words))
    } else if (isFile) {
      out.push(plural("clipboard.files", filePathList.length, "%1 file", "%1 files"))
    } else if (isLink) {
      var domain = ClipboardHistory.urlDomain(fullText)
      if (domain) out.push(domain)
    } else {
      var stats = ClipboardHistory.textStats(fullText)
      out.push(plural("clipboard.chars", stats.chars, "%1 char", "%1 chars") + (row.truncated ? "+" : ""))
      out.push(plural("clipboard.lines", stats.lines, "%1 line", "%1 lines"))
      out.push(plural("clipboard.words", stats.words, "%1 word", "%1 words"))
    }
    if (row.pinned) out.push("󰐃 " + Commons.I18n.t("clipboard.chipPinned", "pinned"))
    return out
  }

  // One chip look for the whole plugin: muted pill, caption text.
  component Chip: Rectangle {
    property string label: ""
    property bool clickable: false
    signal clicked()

    width: chipLabel.implicitWidth + Style.space(10)
    height: chipLabel.implicitHeight + Style.space(4)
    radius: Math.max(2, root.cornerRadius / 3)
    color: clickable && chipMouse.containsMouse ? Util.alpha(root.foreground, 0.16) : root.chipBg

    Text {
      id: chipLabel
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: parent.label
      color: root.foreground
      opacity: parent.clickable ? 0.9 : 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      enabled: parent.clickable
      hoverEnabled: parent.clickable
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Style.space(10)
    visible: root.row !== null

    // ---- header: type + chips
    Flow {
      id: header
      width: parent.width
      spacing: Style.space(6)

      Row {
        spacing: Style.space(6)
        height: typeText.implicitHeight + Style.space(4)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.typeIcon()
          color: root.selectedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Text {
          id: typeText
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: root.typeLabel()
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
      }

      Repeater {
        model: root.chips()
        Chip {
          required property string modelData
          label: modelData
        }
      }
    }

    // ---- body
    Item {
      id: body
      width: parent.width
      height: parent.height - header.height - parent.spacing - (ocrPanel.visible ? ocrPanel.height + parent.spacing : 0)

      // Image: framed, aspect-fit, centered.
      Rectangle {
        id: imageFrame
        visible: root.isImage || (root.isFile && root.imageUrl.length > 0)
        anchors.fill: parent
        radius: root.cornerRadius
        color: Util.alpha(root.foreground, 0.03)
        border.width: Style.normalBorderWidth
        border.color: root.lineColor

        // Decoded at roughly the drawn size, never at the file's own size.
        SizedImage {
          id: image
          anchors.fill: parent
          anchors.margins: Style.space(8)
          url: parent.visible ? root.imageUrl : ""
          asynchronous: true
          smooth: true
        }

        Text {
          anchors.centerIn: parent
          visible: image.status === Image.Error
          textFormat: Text.PlainText
          text: Commons.I18n.t("clipboard.imageMissing", "Image file is missing")
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      // Link: the URL, large and wrapped, with an open action.
      Column {
        visible: root.isLink
        width: parent.width
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.fullText.trim()
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 6
          elide: Text.ElideRight
        }

        Chip {
          label: "󰏌 " + Commons.I18n.t("clipboard.openLink", "Open in browser")
          clickable: true
          onClicked: root.openLink()
        }
      }

      // Files: one row per path.
      ListView {
        visible: root.isFile && !imageFrame.visible
        anchors.fill: parent
        clip: true
        model: root.isFile ? root.filePathList : []
        spacing: Style.space(2)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Row {
          required property string modelData
          width: ListView.view.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: ClipboardHistory.isImagePath(modelData) ? "󰋩" : "󰈔"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width - Style.space(20)
            text: modelData
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideMiddle
          }
        }
      }

      // Text: scrollable.
      Flickable {
        id: textFlick
        visible: !root.isImage && !root.isLink && !root.isFile
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: bodyText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Text {
          id: bodyText
          textFormat: Text.PlainText
          width: textFlick.width
          text: textFlick.visible ? root.fullText : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WrapAnywhere
        }
      }
    }

    // ---- OCR text under an image
    Rectangle {
      id: ocrPanel
      visible: root.isImage && (root.hasOcr || root.ocrBusy)
      width: parent.width
      height: Math.min(Math.round(root.height * 0.3), ocrHeader.height + ocrFlick.contentHeight + Style.space(24))
      radius: root.cornerRadius
      color: Util.alpha(root.foreground, 0.03)
      border.width: Style.normalBorderWidth
      border.color: root.lineColor

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: Style.space(6)

        Row {
          id: ocrHeader
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.ocrBusy
              ? Commons.I18n.t("clipboard.ocrReading", "Reading text…")
              : Commons.I18n.t("clipboard.ocrTitle", "Text in image")
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Chip {
            visible: root.hasOcr
            anchors.verticalCenter: parent.verticalCenter
            label: Commons.I18n.t("common.copy", "Copy")
            clickable: true
            onClicked: root.copyText(root.ocrText)
          }
        }

        Flickable {
          id: ocrFlick
          width: parent.width
          height: parent.height - ocrHeader.height - parent.spacing
          clip: true
          contentWidth: width
          contentHeight: ocrBody.implicitHeight
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: ocrBody
            textFormat: Text.PlainText
            width: ocrFlick.width
            text: root.ocrText
            color: root.foreground
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }
  }
}
