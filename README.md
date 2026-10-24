# BOM Inventory

Native macOS 14+ component inventory, built with SwiftUI and a small AppKit table bridge. The interface follows the supplied charcoal, purple, and yellow references, using the macOS system sans-serif font. No third-party dependencies are required.

## Run

Use the Codex **Run** action or run:

```sh
./script/build_and_run.sh
```

The script builds and stages `dist/BOMInventory.app`. It also supports `--verify`, `--debug`, `--logs`, and `--telemetry` (the latter streams the bundle's subsystem; no remote telemetry is collected).

```sh
swift build
swift test
```

## Features

- The top-left **view switcher** selects PARTS or STORAGE. Storage shows a flat list of assigned locations (plus unassigned parts), inline row descriptions saved to SQLite, and a searchable, paginated table of assigned parts. Click a part row in STORAGE to open the reusable **Part Preview** popup. It shares the PARTS summary, including image preview, labels, QR label export, datasheet, and stock counts. Edit details opens the editor; Go to Part opens the selected component in PARTS. The popup closes on outside clicks, Escape, scrolling, or changing the displayed rows. Select a part to edit it with the pencil button. Adding a part in Storage preselects that location. Hover over a location row and click the pencil to edit its description. Enter or clicking elsewhere saves; Escape cancels. Descriptions remain saved if a location becomes unassigned, but unassigned locations stay out of the list and autocomplete.

- Multiple labels per component, with removable chips, autocomplete, and a persistent recent-label catalog. Return attaches a label to the draft part; saving the part adds it to autocomplete. Cancelling the editor does not create suggestions. The ten most recently used unassigned labels appear when focused, and typing filters the catalog. Names are matched without case sensitivity. Labels, manufacturers, packages, and storage locations appear in autocomplete only while assigned to at least one saved part. Renaming, removing, or deleting the last assignment removes the suggestion; shared values remain available. Old orphaned history is cleaned up automatically.
- All autocomplete menus float above the editor without changing its size and dismiss on outside clicks without consuming the click. Clicking a still-focused input reopens its menu. Manufacturer, Package, and Storage offer the ten most recently used values on focus, filter as you type, and accept custom values. Successful part saves update their recency; stock-only changes do not. Existing inventory values seed these histories automatically.
- Editable tolerance with 1%, 5%, 10%, and 20% presets plus custom values.
- Existing Type values migrate to single labels, with missing tolerance defaulting to empty.
- Create, edit, and delete components; ⌘N adds and ⌘E edits the selected component.
- Resizable table columns, single selection, and pagination with 25/50/100 rows per page.
- Case-insensitive, token-based search across part number, manufacturer, description, package, value, labels, tolerance, and barcode. Tokens can match different fields.
- Images can be imported from disk or the clipboard. The original, a 160-pixel thumbnail, and an 800-pixel hover preview are stored locally. Hovering over the detail image shows the larger popup; clicking opens the original. Existing images gain a hover preview automatically; the editor shows a preview with removal control, and the detail thumbnail opens the original.
- Datasheets can remain HTTP/HTTPS links, be imported from disk, or be downloaded with the arrow button. Downloads upgrade HTTP links to HTTPS automatically and validate the response and PDF contents; the stored link becomes a local PDF path. Local PDFs open in the default PDF app. Imports stay in a private draft directory until Save. Cancel discards them; replacing or removing an attachment cleans up old managed files after a successful save. Deleting a part removes its attachment folder. Source files are preserved.
- Automatically generated, immutable UUID barcode per part; SQLite enforces uniqueness. The label presents it as a QR code and includes part details. Export PNG/PDF or copy the label image.
- Set total on-hand stock, allocate quantities to named projects, and release reservations. Available = on-hand minus allocated. Over-allocation and stock below allocated quantities are rejected.
- Empty inventories start without sample records.

## Storage and extension

Data lives in `~/Library/Application Support/BOMInventory/inventory.sqlite`. Attachments live beside it in `Attachments/`, grouped by part ID. Back up the database and this folder together while the app is closed.

`InventoryRepository` defines the persistence boundary. `SQLiteRepository` currently stores Codable payloads in part/allocation tables alongside a persistent label catalog with a unique barcode constraint and cascading allocation deletion. Schema version is tracked with `PRAGMA user_version`. A future PostgreSQL implementation can conform to the repository interface; remote asynchronous operations, credentials, and migrations will require additional work. Current search and pagination run in memory and are intended for local inventories.

Projects are currently named reservation records rather than standalone project/BOM entities. Cost, worth, purchasing, import, and external catalog integration are outside this iteration. Barcode search supports pasted input and keyboard-wedge USB scanners; there is no camera scanner.
