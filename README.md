# BOM Inventory

Native macOS 14+ component inventory, built with SwiftUI and a small AppKit table bridge. The interface follows the supplied charcoal, purple, and yellow references, using the macOS system sans-serif font. No third-party dependencies are required.

https://github.com/user-attachments/assets/42118366-f694-4c9e-b5c1-083347b58aa1


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

Data lives in `~/Library/Application Support/BOMInventory/inventory.sqlite`. Attachments live beside it in `Attachments/`, grouped by part ID. The Backup control beside API uses restic to back up a consistent SQLite snapshot and the managed attachments together while the app is open.

`InventoryRepository` defines the persistence boundary. `SQLiteRepository` currently stores Codable payloads in part/allocation tables alongside a persistent label catalog with a unique barcode constraint and cascading allocation deletion. Schema version is tracked with `PRAGMA user_version`. A future PostgreSQL implementation can conform to the repository interface; remote asynchronous operations, credentials, and migrations will require additional work. Current search and pagination run in memory and are intended for local inventories.

Projects have persisted descriptions, allocation records, and imported BOM requirements; revision history is outside this iteration. Cost calculations, worth, purchasing, and external catalog integration are outside this iteration. Supplier price columns are retained as custom field text. Barcode search supports pasted input and keyboard-wedge USB scanners; there is no camera scanner.

### CSV parts import and custom fields

- Optional supplier part numbers (SPN) and supplier names appear in the editor, part summary, and parts tables and are searchable. Choose LCSC, DigiKey, Mouser, Newark, or enter another supplier. Existing LCSC data is preserved as LCSC/SPN. CSV exports use named supplier columns such as LCSC or DigiKey.
- Custom name/value fields are editable with plus/minus controls and stored as a JSON object in each SQLite part payload. Existing records default to an empty object. A future PostgreSQL repository can map this object to JSONB.
- The download icon beside search opens CSV import. LCSC exports map LCSC Part Number, Manufacture Part Number, Manufacturer, Package, Description, and Quantity; generic part number/value/tolerance/storage/datasheet/labels/barcode columns are also recognized. Unknown headers are retained as custom fields, including Unit Price and RoHS.
- Review editable CSV cells directly in the main screen, with horizontal and vertical scrolling. Apply and Cancel use yellow backgrounds and black text. Custom-field header checkboxes exclude a whole column from every imported record. Rows start selected; uncheck rows to omit them. Apply matches manufacturer part number or a nonempty supplier/SPN pair, ignoring case and surrounding whitespace. Matches increase stock while preserving existing identity, barcode, attachments, details, and allocations; incoming labels are added, and a missing LCSC number is filled. Repeated rows within the CSV combine as well. Unmatched rows create new parts. Conflicting identifiers that match multiple existing parts stop the whole import for correction. All changes are saved in one transaction. Cancel leaves inventory unchanged. Invalid quantities, missing part numbers, or duplicate barcodes prevent the batch from being saved.

### Description analysis

CSV import adds editable Value, Tolerance, and Labels columns when absent. Description analysis fills missing values and labels for resistors (including 4.7kΩ, 4.7kOhm, 4k7Ohm, 4k7Ω, and 4MOhm), capacitors (pF/nF/uF), inductors (pH/nH/uH), crystals, and oscillators. Crystal frequency takes precedence over load capacitance. Tolerance recognizes percentages and ppm, excluding temperature coefficients such as ppm/℃. Explicit CSV fields and manual edits take priority; editing a description refreshes fields still owned by the analyzer. The part editor also offers Analyze description to fill missing value/tolerance and append an inferred label.

Inductor, Capacitor, Resistor, Crystal, Oscillator, and IC are permanent built-in labels. Other unused labels continue to be pruned.

Import Labels cells support multiple removable chips and autocomplete using existing and draft labels. Type a new label and press Return, select suggestions, or enter comma-separated labels. Pending text is included by Apply even without Return. Label selections on matching parts are added to existing labels.

### Project BOMs and Requested parts

The import icon beside bulk add opens KiCad CSVs with Designator, Footprint, Quantity, Value, and optional LCSC Part # columns. The review stays inside the project pane. Matched shows each original CSV row followed by candidate inventory parts and confirmation checkboxes; only one candidate can be selected per row. Part Preview is available for each candidate. New rows require confirmation, and previously confirmed matches are preselected on repeat imports.

Matching uses exact part number from Value or LCSC number first. Passives use normalized package and numeric value, including equivalent SI units and resistor notation such as 24K, 4K7, 1K5Ohm, and 650R. Supplier part-number packing suffixes can also be offered as candidates for explicit review.

Apply reserves available stock and records unmatched, unchecked, and short-stock quantities in the project's Requested tab. The changes are transactional. Re-importing replaces references present in the new BOM rather than adding a second reservation; different reference grouping is supported, and references outside the import retain their reservations/requests. Project rename/delete includes its BOM requirements. Released reservations return their BOM quantity to Requested.

Requested supports search and CSV export using Designator, Footprint, Quantity, Value, and LCSC Part #. Quantity is the amount still needed, so the export contains only missing quantities rather than the full original BOM.

## License

Licensed under the [MIT License](LICENSE). Copyright © 2026 Vadym Popov.

## HTTP API

Use the **API** button in the bottom-right status bar to configure and start the optional HTTP server. See [api.md](api.md) for endpoints and examples.

## Purchase planning

**PURCHASE** in the view switcher opens a cart with the same part table and detail layout as PARTS. Add/edit/delete items with the main toolbar, specify purchase quantity in the editor, and assign quantities/designators to existing projects from the detail panel. The project's **Purchase** tab lets you add/remove assignments and edit quantity/designators inline. Bulk add shows unassigned cart items with empty editable quantities/designators; Apply saves the edited rows together and Cancel discards them. Clicking rows opens Part Preview with QR and datasheet actions. The cart assignment editor uses project autocomplete. Assigned quantities cannot exceed the cart quantity.

Use **Bulk receive purchases** beside the PURCHASE title, check delivered items, and Apply to add stock to PARTS. Matches by part number or LCSC increase existing stock; new components create inventory records. Project-assigned quantities become reservations. Receipt commits stock, reservations, and cart removal in one transaction. Cancel leaves the cart unchanged. Purchase API routes are documented in [api.md](api.md).

### LCSC Chrome extension

The [Chrome extension](chrome-extension/README.md) imports an LCSC product into
Purchase with a photo, datasheet link, and checkbox-selected project allocations.
It uses the same app logo and supports a configurable local API address and port.

## Niimbot B1 Bluetooth printing

The barcode-label popup includes a **Print** (printer) button. On first use it opens printer controls: power on the B1, close other apps connected to it, click **Scan**, select the printer, and **Connect**. Allow Bluetooth access when macOS asks. The connected device is identified as a B1 (model 4096); B1 Pro and other models are deliberately rejected because they need different resolution/task settings.

Once connected, the printer button prints one label directly. Use the gear button for connection controls, 1–20 copies, and density 1–5. The last successful printer selection and density are remembered. Printing uses a native 384 × 240 monochrome raster for 50 × 30 mm B1 labels at 203 dpi, including the reference protocol's +4-row registration offset. PNG/PDF exports retain their existing resolution and physical size.

The app waits for page acknowledgement, polls the printer's printed-page counter, and sends PrintEnd to feed out the label. A timeout/disconnect reports an unconfirmed print rather than success; check the paper before retrying to avoid duplicate labels. Bluetooth writes are paced and honor CoreBluetooth flow control. Physical printing must be verified on your printer; automated tests cover framing, streaming replies, run-length rows, dimensions, bitmap packing, and QR decoding of the final printer raster.

Protocol adaptation and license: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Part notes

Open **Add notes / Notes** in a part or purchase detail view. The native editor supports bold, italic, underline, and text/images pasted with **⌘V**. Save commits the note; Cancel discards edits. Notes are shared with the part across project previews. Receiving purchases carries their notes into inventory; merging with an existing part combines both notes.

SQLite stores the note text and RTF formatting in the part's JSON payload. Image attachments are separate files beneath the existing managed attachment root, copied on Save and removed when replaced or when the part is deleted. Existing parts default to an empty note. Back up both the database and the attachment folder to preserve images.

The enlarged notes editor is a single WYSIWYG canvas. Text formatting and pasted images appear directly in the document. Type `$V = IR$`, `$$f = \frac{1}{2\pi\sqrt{LC}}$$`, `\(...\)`, or `\[...\]` to render equations in place, or use **Equation**. Click a rendered equation to edit its LaTeX source. Undo/redo supports text, formatting, images, and equation changes. KaTeX is bundled locally and works offline. The original editable math source stays in the note's RTF alongside the text, with image files stored in the managed attachments folder.

### Restic backups

Install `restic` (for example, `brew install restic`), then click **Backup** beside **API**. The badge is grey when restic is missing or no destinations are configured, and orange when restic is available with configured destinations. The app checks PATH and the standard Homebrew locations.

Use **Configure** to add or remove repositories. Enter a destination such as `s3:https://server:port/bucket_name` and credentials as literal `ENV_NAME=ENV_VALUE` lines, for example `AWS_ACCESS_KEY_ID=...` and `AWS_SECRET_ACCESS_KEY=...`. Values are passed directly to restic without shell expansion or quote removal. Settings and endpoint credentials are saved in `~/Library/Application Support/BOMInventory/backup-settings.json` with owner-only file permissions; this settings file is excluded from backup payloads.

For a new repository, choose **Initialize…**, then enter and confirm a password. Existing repositories can be saved without initialization. **Sync** asks for the password once and backs up to each configured destination in order, continuing if a destination fails. All destinations in a Sync operation must use the same password. The password is passed via `RESTIC_PASSWORD` for the operation and is never saved. Keep it safe: restic needs it to restore your backups.

The popup shows the last successful backup recorded by this app for each destination and the latest operation's raw combined output and exit statuses. Output appears when each repository command completes. An exit status other than zero is not recorded as a successful backup. Backups contain `inventory.sqlite` and `Attachments/` and use the restic tag `bom-inventory`. Restore with restic to a separate folder, close the app, and replace the database and attachments in the application support directory together.

### Project notes

The Projects list has an untitled notes column after Description. Every row has a notes button: gray for an empty note, yellow when a note exists. Click it to open the same WYSIWYG editor used for part notes, including clipboard images, formatting, and editable equations. Project note text/formatting lives in SQLite's `project_notes` table; images use a stable `project-…` attachment folder. Renaming a project preserves its note and images. Clearing notes or deleting the project cleans up the corresponding images.
