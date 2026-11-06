function normalizeEntry(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  var entry = null
  if (type === "text") {
    var text = String(value.text || "")
    if (text.trim().length > 0) entry = { type: "text", text: text }
  } else if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    // OCR text is filled in lazily by the picker; "" records "ran, nothing found".
    if (typeof value.ocr === "string") entry.ocr = value.ocr
  }

  // Pinned is the only user-set field; keep it only when true so the file
  // stays byte-compatible with the built-in plugin for unpinned entries.
  if (entry && value.pinned === true) entry.pinned = true
  return entry
}

function isPinned(entry) {
  return !!(entry && entry.pinned === true)
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function indexOfKey(history, key) {
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length; i++) {
    if (entryKey(normalizeEntry(values[i])) === key) return i
  }
  return -1
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next

    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

function addEntry(history, entry, limit) {
  var normalized = normalizeEntry(entry)
  var max = limit === undefined || limit === null ? 100 : Number(limit)
  if (isNaN(max)) max = 100
  max = Math.max(0, max)
  if (!normalized) return Array.isArray(history) ? history.slice(0, max) : []
  if (max === 0) return []

  var key = entryKey(normalized)
  var values = Array.isArray(history) ? history : []
  var rest = []

  for (var i = 0; i < values.length; i++) {
    var existing = normalizeEntry(values[i])
    if (!existing) continue
    if (entryKey(existing) === key) {
      // Re-copying a pinned entry keeps its pin.
      if (isPinned(existing)) normalized.pinned = true
      continue
    }
    rest.push(existing)
  }

  var next = [normalized]
  // Trim unpinned entries only, oldest first: pins never age out of the cap.
  var room = max - 1
  var pinnedCount = 0
  for (var j = 0; j < rest.length; j++) if (isPinned(rest[j])) pinnedCount++
  var unpinnedRoom = Math.max(0, room - pinnedCount)
  for (var k = 0; k < rest.length; k++) {
    if (isPinned(rest[k])) {
      next.push(rest[k])
    } else if (unpinnedRoom > 0) {
      next.push(rest[k])
      unpinnedRoom--
    }
  }

  return next
}

// Pinned entries are only removed with force (the picker confirms first).
function removeEntryAt(history, index, force) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()
  if (isPinned(values[target]) && !force) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

function togglePinAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  var entry = normalizeEntry(next[target])
  if (!entry) return next
  if (isPinned(entry)) delete entry.pinned
  else entry.pinned = true
  next[target] = entry
  return next
}

function unpinAll(history) {
  var values = Array.isArray(history) ? history : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue
    delete entry.pinned
    next.push(entry)
  }
  return next
}

// Clearing keeps pins: they were chosen deliberately, and Delete refuses
// them one at a time, so a bulk clear should not get around that.
function clearHistory(history) {
  var values = Array.isArray(history) ? history : []
  var kept = []
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (entry && isPinned(entry)) kept.push(entry)
  }
  return kept
}

// Category chips. "all" matches everything; pinned rows keep their own
// section so there is no "pinned" category.
var categories = ["all", "text", "links", "images", "files"]

function isLinkText(text) {
  return /^\s*https?:\/\/[^\s]+\s*$/i.test(String(text || ""))
}

function categoryOf(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "images"
  if (filePaths(entry).length > 0) return "files"
  if (isLinkText(entry.text)) return "links"
  return "text"
}

function categoryLabel(category, tr) {
  var t = translator(tr)
  switch (String(category || "")) {
  case "all": return t("clipboard.categoryAll", "All")
  case "text": return t("clipboard.categoryText", "Text")
  case "links": return t("clipboard.categoryLinks", "Links")
  case "images": return t("clipboard.categoryImages", "Images")
  case "files": return t("clipboard.categoryFiles", "Files")
  default: return String(category || "")
  }
}

function nextCategory(current, delta) {
  var at = categories.indexOf(String(current || "all"))
  if (at < 0) at = 0
  return categories[(at + delta + categories.length) % categories.length]
}

function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "") + " " + String(entry.ocr || "")
  return String(entry.text || "") + " " + fileEntryText(entry)
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}


// tr is an optional translate(key, english) from the QML side (I18n.t),
// trn its plural form (I18n.tn) and fmt a number formatter
// (I18n.formatNumber); without them the English text and plain digits
// stand, which is what the Node tests assert.
function translator(tr) {
  return typeof tr === "function" ? tr : function(key, english) { return english }
}

function fileEntryText(entry, tr, trn, fmt) {
  var tn = typeof trn === "function" ? trn : function(key, count, english) { return count === 1 ? english.one : english.other }
  var number = typeof fmt === "function" ? fmt : function(v) { return String(v) }
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return tn("clipboard.files", paths.length, { one: "%1 file", other: "%1 files" }).replace("%1", number(paths.length))
}

function imagePreviewText(entry, tr) {
  var t = translator(tr)
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return t("clipboard.image", "Image")

  var screenshot = String(entry && entry.mime || "") === "image/png"
  var pattern = screenshot
    ? t("clipboard.screenshotFrom", "Screenshot from %1")
    : t("clipboard.imageFrom", "Image from %1")
  return pattern.replace("%1", timestamp)
}

function previewText(entry, tr, trn, fmt) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry, tr)
  var fileText = fileEntryText(entry, tr, trn, fmt)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

function textStats(text) {
  var value = String(text || "")
  if (!value) return { chars: 0, lines: 0, words: 0 }
  var words = value.trim() ? value.trim().split(/\s+/).length : 0
  return { chars: value.length, lines: value.split(/\r?\n/).length, words: words }
}

function urlDomain(url) {
  var m = /^\s*[a-z][a-z0-9+.-]*:\/\/([^\/?#\s]+)/i.exec(String(url || ""))
  return m ? m[1].replace(/^www\./i, "") : ""
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

// Set OCR text on every image entry with this path; returns a new array.
function setOcrForPath(history, path, text) {
  var values = Array.isArray(history) ? history : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue
    if (entry.type === "image" && entry.path === path) entry.ocr = String(text || "")
    next.push(entry)
  }
  return next
}

// The picker only ever searches and renders a prefix of an entry, so scan and
// render just that much. A single huge paste otherwise costs hundreds of
// megabytes of string work on every keystroke and stalls the whole shell.
// Pasting reads the full entry back from history by index, so nothing is lost.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  // Cut on a line break so a file:// URI never truncates into a bogus path.
  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  var capped = { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit), truncated: true }
  if (isPinned(entry)) capped.pinned = true
  return capped
}

// Rows come out pinned first (newest pin first), then the rest newest first,
// each tagged with its section so the list can draw a divider between them.
// `category` is one of `categories`; anything else behaves as "all".
function displayRows(history, query, limit, tr, trn, fmt, category) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var wanted = categories.indexOf(String(category || "all")) > 0 ? String(category) : ""
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  if (max === 0) return []

  var pinned = []
  var recent = []

  // Scan everything: the limit applies to unpinned rows only, and a pin can
  // sit anywhere in the history.
  for (var i = 0; i < values.length; i++) {
    var entry = cappedEntry(normalizeEntry(values[i]))
    if (!entry) continue
    var isPin = isPinned(entry)
    if (!isPin && recent.length >= max) continue
    if (needle && searchableText(entry).toLowerCase().indexOf(needle) < 0) continue
    if (wanted && categoryOf(entry) !== wanted) continue

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var isImage = entry.type === "image"
    var entryCategory = categoryOf(entry)
    var previewPath = isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "")
    var row = {
      entryType: isFile ? "file" : entry.type,
      fullText: isImage ? "" : fullText(entry),
      previewText: previewText(entry, tr, trn, fmt),
      previewImage: previewPath,
      path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      pinned: isPin,
      section: isPin ? "pinned" : "recent",
      category: entryCategory,
      capturedAt: isImage ? String(entry.capturedAt || "") : "",
      ocr: isImage ? (typeof entry.ocr === "string" ? entry.ocr : null) : null,
      truncated: !!entry.truncated,
      index: i
    }
    if (isPin) pinned.push(row)
    else recent.push(row)
  }

  return pinned.concat(recent)
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeEntry: normalizeEntry,
    entryKey: entryKey,
    indexOfKey: indexOfKey,
    parseHistory: parseHistory,
    addEntry: addEntry,
    removeEntryAt: removeEntryAt,
    togglePinAt: togglePinAt,
    unpinAll: unpinAll,
    isPinned: isPinned,
    clearHistory: clearHistory,
    categories: categories,
    categoryOf: categoryOf,
    categoryLabel: categoryLabel,
    nextCategory: nextCategory,
    isLinkText: isLinkText,
    textStats: textStats,
    urlDomain: urlDomain,
    isImagePath: isImagePath,
    setOcrForPath: setOcrForPath,
    parseEntryJson: parseEntryJson,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    displayRows: displayRows
  }
}
