# NcduUI

A native macOS disk-usage analyzer built with SwiftUI. It reimplements the core
of [ncdu](https://dev.yorhel.nl/ncdu) (NCurses Disk Usage) with a modern,
mouse-and-keyboard friendly interface instead of an ncurses TUI.

The C source of ncdu is vendored under [`reference/ncdu`](reference/ncdu) and was
used as the behavioral reference for the scanning engine.

**Requirements:** macOS 14 (Sonoma) or later

## Try it (unsigned build)

Pre-built releases are attached to [GitHub Releases](https://github.com/FelixRobb/NcduUI/releases). These builds are **not notarized** and are signed ad hoc for local testing only.

1. Download `NcduUI-*-macOS-unsigned.zip` from the latest release.
2. Unzip and move `NcduUI.app` to Applications (or run from anywhere).
3. On first launch, macOS may block the app. Either:
   - **Right-click → Open** on `NcduUI.app`, then confirm Open, or
   - Remove the quarantine flag: `xattr -cr /Applications/NcduUI.app`

To build the same zip locally:

```bash
chmod +x scripts/package-unsigned.sh
./scripts/package-unsigned.sh
```

Tag a version to publish a release automatically (GitHub Actions builds and uploads the zip):

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Features

- Fast recursive scan using `lstat` to measure **real disk usage** (`st_blocks * 512`),
  not just apparent file size.
- **Overview dashboard** after each scan: a squarified **treemap** of the
  composition, the largest folders/files, and **cleanup suggestions** that flag
  commonly reclaimable items (node_modules, Xcode DerivedData, caches, build
  folders, logs, `.DS_Store`, Trash, …) with one-click Move-to-Trash / reveal.
- **Finder-style column (Miller) browser** for fast drill-down navigation, with
  a live file preview pane and a breadcrumb path bar.
- **macOS inspector sidebar** on the right with full item details.
- Toggle between **Disk Usage** and **Apparent Size** at any time.
- **Hard-link aware**: a shared inode is counted only once per directory subtree,
  matching ncdu's accounting (ported from `dir_mem.c`).
- Sortable by disk usage, apparent size, name, item count, or modified date,
  ascending/descending, with optional "folders first" grouping.
- Live, cancellable scan progress (items, bytes, current path).
- Show/hide hidden items, a **minimum-size** browse filter, and per-folder search.
- Safe destructive actions: **Move to Trash** (with confirmation), plus
  **Reveal in Finder** and **Open**.

### Scan filters (ported from ncdu)

Configured from the welcome screen or the toolbar; applied on the next scan:

- **Exclude patterns** — glob patterns matched against names and full paths,
  faithful to ncdu's `--exclude` (`fnmatch` against the path and every sub-path).
- **Exclude caches** — skip directories tagged with `CACHEDIR.TAG`
  (ncdu `--exclude-caches`).
- **Stay on the same filesystem** — don't cross into other mounted volumes
  (ncdu `-x`).
- **Follow symlinks** — count symlink targets for files (ncdu `-L`).

## Build & Run

Requires Xcode 16 or later (built and tested with Xcode 26).

Open in Xcode:

```bash
open NcduUI.xcodeproj
```

Then press Run (Cmd-R).

Or build from the command line:

```bash
xcodebuild -project NcduUI.xcodeproj -scheme NcduUI -configuration Release \
  -derivedDataPath ./build build
open ./build/Build/Products/Release/NcduUI.app
```

## Full Disk Access

Protected folders (Mail, Messages, parts of `/Library`, etc.) require **Full Disk Access**
so NcduUI can scan them without repeated permission prompts.

The app detects this automatically and can guide you:

1. **Welcome screen** — orange banner with “Learn How…”
2. **Help → Full Disk Access Guide…** — step-by-step instructions anytime
3. **First launch** — guide opens once if access is not yet granted

From the guide you can jump to **System Settings**, **Reveal App in Finder** (to drag
into the list), and **Check Again** after enabling. Quit and reopen the app when done.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open Folder | ⌘O |
| Scan Filters | ⌘⇧F |
| Rescan | ⌘R |
| Cancel Scan | ⌘. |
| Overview | ⌘1 |
| Browse | ⌘2 |
| Toggle Inspector | ⌘⌥I |
| Show/Hide Hidden Items | ⌘⇧H |
| Go Up | ⌘↑ |
| Open Item | ⌘↓ |
| Reveal in Finder | ⌘⇧R |
| Move to Trash | ⌘⌫ |
| Filter (search) | ⌘F |

Menus: **File**, **View**, **Go**, **Item**, and **Help**.

## Architecture

| Swift file | Responsibility | ncdu reference |
| --- | --- | --- |
| `DiskScanner.swift` | Recursive `lstat` scan, disk vs. apparent size, hard-link dedup, exclude patterns, cache/same-fs/symlink filters, progress, cancellation | `src/dir_scan.c`, `src/dir_mem.c`, `src/exclude.c` |
| `FileNode.swift` | Tree node model (size, asize, dev, ino, items, flags) | `src/global.h` |
| `SizeFormatter.swift` | Human-readable sizes | `src/util.c` (`formatsize`) |
| `ScanViewModel.swift` | App state, column navigation, sorting/filtering, Trash action | `src/dirlist.c`, `src/delete.c` |
| `JunkAnalyzer.swift` | Cleanup suggestions and largest-item analysis | — |
| `TreemapView.swift` | Squarified treemap visualization | — |
| `OverviewView.swift` | Post-scan dashboard | — |
| `ColumnBrowserView.swift` | Finder-style column navigation | `src/browser.c` |
| `ScanFiltersView.swift` | Exclude/scan filter editor | `src/main.c`, `src/exclude.c` |
| `InfoPanelView.swift` | Right inspector sidebar | — |

## Project layout

```
NcduUI/             App source, entitlements, assets
NcduUI.xcodeproj    Xcode project
reference/ncdu/     Vendored ncdu C source (behavioral reference)
scripts/            Local packaging helpers
```

Bundle ID: `com.felix.NcduUI`.

## Notes

- Deletion always moves items to the Trash; there is no permanent delete.
- Disk-usage totals match `du` and `ncdu` (verified against `du -sk`).

## License

MIT — see [LICENSE](LICENSE).
