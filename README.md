# Clipnest

Omarchy's clipboard manager, extended. Same history file, same capture flow,
same paste scripts as the built-in `omarchy.clipboard`, plus:

- **Pins** — `Tab` pins an entry. Pins sit in their own section at the top,
  survive the history cap and clear-all, and `Del` never touches them.
- **Categories** — All / Text / Links / Images / Files tabs under the search
  bar. `←` `→` cycles, or click.
- **Previews per type** — images framed with their dimensions, links with
  their domain and an open action, text with char/line/word counts, file lists
  one path per row.
- **OCR** — the first time an image is previewed, `tesseract` reads its text.
  The text shows under the image, is copyable, and is searchable from then on.
- **Key-hint footer** — only the keys that apply to the selected entry.
- `Ctrl+N` / `Ctrl+P` navigation, `Ctrl+O` open, copy-path and copy-text.

## Install

```bash
omarchy plugin add https://github.com/Akshad135/real-clipboard.git --enable
```

Omarchy routes its own clipboard shortcuts (`Super+Ctrl+V`, and any binding
that targets `omarchy.clipboard`) to this plugin while it is enabled. Disable
it to get the built-in back:

```bash
omarchy plugin disable akshad135.clipnest
```

Keep the built-in `omarchy.clipboard` disabled while this is enabled (the
`--enable` above does that). Both running at once means two capture watchers
writing the same history file.

Dependencies: `wl-clipboard`, `jq`, `wtype`, `imagemagick` (all part of Omarchy's base install; without imagemagick the dimensions chip is simply absent).
Optional: `tesseract` and a language pack (`omarchy pkg add tesseract
tesseract-data-eng`) for OCR. Without it, images simply have no text panel.

## Keys

| Key | Action |
| --- | --- |
| `↑` `↓` / `Ctrl+N` `Ctrl+P` | move |
| `PgUp` `PgDn` / `Home` `End` | jump |
| `←` `→` | switch category |
| `Enter` | copy and paste into the focused window |
| `Shift+Enter` | copy only |
| `Ctrl+O` / `Alt+Enter` | open: links in the browser, images in the viewer, text in the editor |
| `Ctrl+Shift+P` | copy the file path (images and files) |
| `Ctrl+Shift+C` | copy as plain text; for images, the OCR text |
| `Tab` | pin / unpin |
| `Shift+Tab` | unpin all (confirms) |
| `Del` | delete; does nothing on a pin |
| `Ctrl+Del` | delete a pinned entry (confirms) |
| `Shift+Del` | clear history, keeping pins (confirms) |
| `Ctrl+U` | clear the search |
| `Esc` | clear the search, then close |

## Data

History lives in `~/.local/state/omarchy/clipboard-history.json`, the same
file the built-in uses. Entries gain two optional fields, `pinned` and `ocr`;
the built-in ignores both, so switching back loses nothing but the pins.

## Development

```bash
git clone https://github.com/Akshad135/real-clipboard.git
ln -sTfn "$PWD/real-clipboard" ~/.config/omarchy/plugins/akshad135.clipnest
omarchy-shell shell rescanPlugins && omarchy plugin enable akshad135.clipnest
tests/run.sh
```

The shell caches plugin QML; after editing, `omarchy restart shell`.

Built on the clipboard plugin that ships with [Omarchy](https://omarchy.org). MIT.
