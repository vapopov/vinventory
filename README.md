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

- PROJECTS supports independent projects and projects created through stock allocations. Compact Add/Edit/Delete controls on the list title row open name/description dialogs; renaming updates allocations, and confirmed deletion releases all project allocations. The bulk-add icon beside ALLOCATIONS switches to searchable, unallocated parts with empty Qty/Designators. Edit either cell using its pencil, then Apply to save filled rows together; Cancel discards the draft. Drafts persist across search and pagination. Designators infer quantity; manual quantity is also supported. Stock validation prevents partial batches. Its allocation table has row numbers, quantities, per-allocation Designators, Release buttons, and the reusable Part Preview. Designators are optional references (for example `C16-C20`, `IC2`, or `R3, R4, R11`). Manually changing them recalculates quantity from unique references and inclusive ranges; clearing them preserves quantity. Quantity can also be edited independently. Hover either cell and use its pencil; Enter/outside-click saves and Escape cancels. Updates cannot exceed available stock. Release first reveals cancel/approve icons. The PARTS allocation tab has a pencil editor for quantity and designators. Search includes part fields and designators. Existing allocations migrate automatically with empty designators. Projects and their descriptions remain after all reservations are released.

- The top-left **view switcher** selects PARTS, STORAGE, or PROJECTS. Storage shows a flat list of persistent locations, a permanent (no storage) entry for unassigned parts, and a searchable, paginated parts table. Compact Add/Edit/Delete controls on the LOCATIONS title row open name/description dialogs. Renaming updates part assignments; confirmed deletion moves parts to (no storage). The fixed entry cannot be edited or deleted. Click a part row in STORAGE to open the reusable **Part Preview** popup. It shares the PARTS summary, including image preview, labels, QR label export, datasheet, and stock counts. Edit details opens the editor; Go to Part opens the selected component in PARTS. The popup closes on outside clicks, Escape, scrolling, or changing the displayed rows. Select a part to edit it with the pencil button. Adding a part in Storage preselects that location. Empty storage locations and projects persist until explicitly deleted. Empty named locations are available in Storage autocomplete after recent assignments.

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

Projects have persisted descriptions, allocation records, and imported BOM requirements; revision history is outside this iteration. Cost calculations, worth, purchasing, and external catalog integration are outside this iteration. Supplier price columns are retained as custom field text. Barcode search supports pasted input and keyboard-wedge USB scanners; there is no camera scanner.

### CSV parts import and custom fields

- Optional LCSC supplier numbers appear in the editor, part summary, and parts tables and are searchable.
- Custom name/value fields are editable with plus/minus controls and stored as a JSON object in each SQLite part payload. Existing records default to an empty object. A future PostgreSQL repository can map this object to JSONB.
- The download icon beside search opens CSV import. LCSC exports map LCSC Part Number, Manufacture Part Number, Manufacturer, Package, Description, and Quantity; generic part number/value/tolerance/storage/datasheet/labels/barcode columns are also recognized. Unknown headers are retained as custom fields, including Unit Price and RoHS.
- Review editable CSV cells directly in the main screen, with horizontal and vertical scrolling. Apply and Cancel use yellow backgrounds and black text. Custom-field header checkboxes exclude a whole column from every imported record. Rows start selected; uncheck rows to omit them. Apply matches manufacturer part number or nonempty LCSC number, ignoring case and surrounding whitespace. Matches increase stock while preserving existing identity, barcode, attachments, details, and allocations; incoming labels are added, and a missing LCSC number is filled. Repeated rows within the CSV combine as well. Unmatched rows create new parts. Conflicting identifiers that match multiple existing parts stop the whole import for correction. All changes are saved in one transaction. Cancel leaves inventory unchanged. Invalid quantities, missing part numbers, or duplicate barcodes prevent the batch from being saved.

### Description analysis

CSV import adds editable Value, Tolerance, and Labels columns when absent. Description analysis fills missing values and labels for resistors (including 4.7kΩ, 4.7kOhm, 4k7Ohm, 4k7Ω, and 4MOhm), capacitors (pF/nF/uF), inductors (pH/nH/uH), crystals, and oscillators. Crystal frequency takes precedence over load capacitance. Tolerance recognizes percentages and ppm, excluding temperature coefficients such as ppm/℃. Explicit CSV fields and manual edits take priority; editing a description refreshes fields still owned by the analyzer. The part editor also offers Analyze description to fill missing value/tolerance and append an inferred label.

Inductor, Capacitor, Resistor, Crystal, Oscillator, and IC are permanent built-in labels. Other unused labels continue to be pruned.

Import Labels cells support multiple removable chips and autocomplete using existing and draft labels. Type a new label and press Return, select suggestions, or enter comma-separated labels. Pending text is included by Apply even without Return. Label selections on matching parts are added to existing labels.

### Project BOMs and Requested parts

The import icon beside bulk add opens KiCad CSVs with Designator, Footprint, Quantity, Value, and optional LCSC Part # columns. The review stays inside the project pane. Matched shows each original CSV row followed by candidate inventory parts and confirmation checkboxes; only one candidate can be selected per row. Part Preview is available for each candidate. New rows require confirmation, and previously confirmed matches are preselected on repeat imports.

Matching uses exact part number from Value or LCSC number first. Passives use normalized package and numeric value, including equivalent SI units and resistor notation such as 24K, 4K7, 1K5Ohm, and 650R. Supplier part-number packing suffixes can also be offered as candidates for explicit review.

Apply reserves available stock and records unmatched, unchecked, and short-stock quantities in the project's Requested tab. The changes are transactional. Re-importing replaces references present in the new BOM rather than adding a second reservation; different reference grouping is supported, and references outside the import retain their reservations/requests. Project rename/delete includes its BOM requirements. Released reservations return their BOM quantity to Requested.

Requested supports search and CSV export using Designator, Footprint, Quantity, Value, and LCSC Part #. Quantity is the amount still needed, so the export contains only missing quantities rather than the full original BOM.
