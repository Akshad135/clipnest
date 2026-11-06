// Logic tests for ClipboardHistory.js.
import { test } from "node:test"
import assert from "node:assert/strict"
import { createRequire } from "node:module"

const require = createRequire(import.meta.url)
const H = require("../ClipboardHistory.js")

const text = (t, extra = {}) => ({ type: "text", text: t, ...extra })

test("normalizeEntry keeps pinned only when true", () => {
  assert.deepEqual(H.normalizeEntry(text("a", { pinned: true })), { type: "text", text: "a", pinned: true })
  assert.deepEqual(H.normalizeEntry(text("a", { pinned: false })), { type: "text", text: "a" })
  assert.deepEqual(H.normalizeEntry(text("a", { pinned: "yes" })), { type: "text", text: "a" })
})

test("togglePinAt flips the flag and leaves other entries alone", () => {
  const h = [text("a"), text("b")]
  const pinned = H.togglePinAt(h, 1)
  assert.equal(H.isPinned(pinned[1]), true)
  assert.equal(H.isPinned(pinned[0]), false)
  assert.equal(H.isPinned(h[1]), false, "input not mutated")
  const unpinned = H.togglePinAt(pinned, 1)
  assert.deepEqual(unpinned[1], text("b"))
})

test("removeEntryAt refuses pinned entries unless forced", () => {
  const h = [text("a", { pinned: true }), text("b")]
  assert.equal(H.removeEntryAt(h, 0).length, 2)
  assert.equal(H.removeEntryAt(h, 1).length, 1)
  assert.deepEqual(H.removeEntryAt(h, 0, true), [text("b")])
})

test("unpinAll drops every pin and nothing else", () => {
  const h = [text("a", { pinned: true }), text("b"), text("c", { pinned: true })]
  assert.deepEqual(H.unpinAll(h), [text("a"), text("b"), text("c")])
})

test("clearHistory keeps pins", () => {
  const h = [text("a"), text("b", { pinned: true }), text("c")]
  assert.deepEqual(H.clearHistory(h), [text("b", { pinned: true })])
  assert.deepEqual(H.clearHistory([]), [])
})

test("addEntry re-copy of a pinned entry stays pinned and moves to top", () => {
  const h = [text("x"), text("p", { pinned: true })]
  const next = H.addEntry(h, text("p"), 100)
  assert.deepEqual(next, [text("p", { pinned: true }), text("x")])
})

test("addEntry cap trims unpinned entries, never pins", () => {
  const h = [text("1"), text("p", { pinned: true }), text("2"), text("3")]
  const next = H.addEntry(h, text("new"), 3)
  assert.deepEqual(next, [text("new"), text("1"), text("p", { pinned: true })])
})

test("categoryOf", () => {
  assert.equal(H.categoryOf(text("hello")), "text")
  assert.equal(H.categoryOf(text("https://example.com/x?y=1")), "links")
  assert.equal(H.categoryOf(text("see https://example.com")), "text")
  assert.equal(H.categoryOf(text("file:///home/u/a.txt")), "files")
  assert.equal(H.categoryOf({ type: "image", path: "/p.png" }), "images")
})

test("nextCategory wraps both ways", () => {
  assert.equal(H.nextCategory("all", 1), "text")
  assert.equal(H.nextCategory("all", -1), "files")
  assert.equal(H.nextCategory("files", 1), "all")
  assert.equal(H.nextCategory("bogus", 1), "text")
})

test("displayRows puts pins first, tags sections, keeps history index", () => {
  const h = [text("new"), text("p", { pinned: true }), text("old")]
  const rows = H.displayRows(h, "", 50)
  assert.deepEqual(rows.map(r => [r.previewText, r.section, r.index]), [
    ["p", "pinned", 1],
    ["new", "recent", 0],
    ["old", "recent", 2],
  ])
})

test("displayRows filters by category; all and unknown match everything", () => {
  const h = [text("https://a.io"), text("word"), { type: "image", path: "/i.png" }, text("file:///f")]
  const names = (c) => H.displayRows(h, "", 50, undefined, undefined, undefined, c).map(r => r.entryType)
  assert.deepEqual(names("all"), ["text", "text", "image", "file"])
  assert.deepEqual(names(undefined), ["text", "text", "image", "file"])
  assert.deepEqual(names("links"), ["text"])
  assert.deepEqual(H.displayRows(h, "", 50, undefined, undefined, undefined, "links")[0].previewText, "https://a.io")
  assert.deepEqual(names("text"), ["text"])
  assert.deepEqual(names("images"), ["image"])
  assert.deepEqual(names("files"), ["file"])
})

test("displayRows finds pins past the unpinned limit", () => {
  const h = []
  for (let i = 0; i < 60; i++) h.push(text("u" + i))
  h.push(text("late pin", { pinned: true }))
  const rows = H.displayRows(h, "", 50)
  assert.equal(rows[0].previewText, "late pin")
  assert.equal(rows.length, 51)
})

test("displayRows limit counts unpinned rows only", () => {
  const h = [text("p1", { pinned: true }), text("a"), text("b"), text("c")]
  const rows = H.displayRows(h, "", 2)
  assert.deepEqual(rows.map(r => r.previewText), ["p1", "a", "b"])
})
