# BOM Inventory HTTP API

Click **API** in the bottom-right status bar to configure the address and port, then click **Start server**. Defaults: `127.0.0.1:8080`. Settings and enabled state persist across app launches. **Apply & restart** changes the listener; **Stop** disables it. The app must remain running.

This is plain HTTP without authentication. Binding to `127.0.0.1` limits access to your Mac; `0.0.0.0` listens on all IPv4 interfaces. Only bind to a trusted network when allowing remote clients.

Base URL in examples: `http://127.0.0.1:8080`. Send JSON objects with `Content-Type: application/json`. Responses are JSON. No TLS, file uploads, chunked requests, WebSockets, or browser CORS support. Each connection handles one request and closes. Maximum complete request size: 1 MiB; connection timeout: 15 seconds.

## Routes

| Method | Path | Operation |
|---|---|---|
| GET | `/health` | Server status |
| GET | `/v1/parts?q=...` | List/search parts; omit `q` for all |
| POST | `/v1/parts` | Create a part |
| GET | `/v1/parts/{id}` | Get a part |
| PATCH | `/v1/parts/{id}` | Edit supplied fields |
| DELETE | `/v1/parts/{id}` | Delete part, allocations, and attachments |
| GET | `/v1/projects` | List project names and descriptions |
| POST | `/v1/projects` | Create a project |
| GET | `/v1/projects/{name}` | Get project |
| PATCH | `/v1/projects/{name}` | Rename/change description |
| DELETE | `/v1/projects/{name}` | Delete project and requests; release allocations |
| GET | `/v1/projects/{name}/allocations` | List allocated parts |
| POST | `/v1/projects/{name}/allocations` | Allocate stock; merge with existing allocation of same part |
| PATCH | `/v1/projects/{name}/allocations/{id}` | Change allocation quantity/designators |
| DELETE | `/v1/projects/{name}/allocations/{id}` | Release allocation back to available stock |
| GET | `/v1/projects/{name}/requested` | List unmet requirements |
| POST | `/v1/projects/{name}/requested` | Add a requested part |
| PATCH | `/v1/projects/{name}/requested/{id}` | Edit requested part |
| DELETE | `/v1/projects/{name}/requested/{id}` | Remove outstanding request; keep already allocated stock |

URL-encode project names as one path segment, e.g. `USB%20Hub`. IDs are returned in responses. Successful reads/updates/deletions return `200`; creation returns `201`. Invalid JSON, data, or stock operations return `400`; missing records return `404`; unsupported methods/routes return `405`. Errors have the form `{"error":"message"}`. Lists are JSON arrays without pagination.

## Parts

Create requires `number`. Editable fields: `number`, `manufacturer`, `lcsc`, `description`, `package`, `value`, `tolerance`, `stock`, `storage`, `datasheet`, `labels` (string array), `customFields` (string-to-string object), and `barcode`. `id` and `image` are not editable through this API. IDs and unique barcodes are generated when omitted. Stock is a nonnegative integer and cannot fall below allocated quantity. Label arrays and custom-field objects replace the previous values when supplied in PATCH; omitted fields stay unchanged.

`datasheet` accepts a web URL or an accessible local PDF path; it does not download remote files. Image uploads are not implemented. Allocation records, rather than part stock edits, control project reservations.

```sh
curl http://127.0.0.1:8080/health

curl -X POST http://127.0.0.1:8080/v1/parts \
  -H 'Content-Type: application/json' \
  -d '{"number":"RC0402FR-074K7L","manufacturer":"YAGEO","lcsc":"C105871","description":"4.7kΩ resistor","value":"4.7kΩ","package":"0402","tolerance":"1%","stock":100,"labels":["Resistor"],"customFields":{"Voltage":"50V"}}'

curl 'http://127.0.0.1:8080/v1/parts?q=4.7k'

curl -X PATCH http://127.0.0.1:8080/v1/parts/PART_ID \
  -H 'Content-Type: application/json' -d '{"stock":150,"storage":"Drawer A"}'

curl -X DELETE http://127.0.0.1:8080/v1/parts/PART_ID
```

## Projects and allocated parts

Create a project with `name` and optional `description`. PATCH accepts either or both. Renaming also updates its allocations and BOM requests.

```sh
curl -X POST http://127.0.0.1:8080/v1/projects \
  -H 'Content-Type: application/json' -d '{"name":"USB Hub","description":"Prototype"}'

curl -X PATCH http://127.0.0.1:8080/v1/projects/USB%20Hub \
  -H 'Content-Type: application/json' -d '{"description":"Revision B"}'

curl -X POST http://127.0.0.1:8080/v1/projects/USB%20Hub/allocations \
  -H 'Content-Type: application/json' -d '{"partID":"PART_ID","quantity":3,"designators":"R1, R2, R3"}'

curl http://127.0.0.1:8080/v1/projects/USB%20Hub/allocations

curl -X PATCH http://127.0.0.1:8080/v1/projects/USB%20Hub/allocations/ALLOCATION_ID \
  -H 'Content-Type: application/json' -d '{"designators":"R1-R5"}'

curl -X DELETE http://127.0.0.1:8080/v1/projects/USB%20Hub/allocations/ALLOCATION_ID
```

POST allocation requires `partID` and a positive integer `quantity`; `designators` is optional. Repeated POSTs add quantities and append designators, matching the UI. PATCH `quantity` is the replacement total. Editing `designators` recalculates quantity when references are supplied, taking precedence over an explicit quantity. Allocations cannot exceed available stock. These endpoints manage reservations; they do not edit the underlying part description or stock. Use `/v1/parts/{id}` for those changes.

## Requested parts

POST/PATCH fields: `value` (part number or component value), `package`, `lcsc`, `designators`, `quantity`. `value` is required on create, `quantity` defaults to 1 and must be positive. PATCH preserves omitted fields. Quantity means the **outstanding quantity**, so editing a shortage preserves any already allocated quantity. Request designators do not automatically change quantity.

```sh
curl -X POST http://127.0.0.1:8080/v1/projects/USB%20Hub/requested \
  -H 'Content-Type: application/json' \
  -d '{"value":"10uF","package":"0603","quantity":5,"designators":"C1-C5","lcsc":"C19702"}'

curl http://127.0.0.1:8080/v1/projects/USB%20Hub/requested

curl -X PATCH http://127.0.0.1:8080/v1/projects/USB%20Hub/requested/REQUEST_ID \
  -H 'Content-Type: application/json' -d '{"quantity":8,"designators":"C1-C8"}'

curl -X DELETE http://127.0.0.1:8080/v1/projects/USB%20Hub/requested/REQUEST_ID
```

List responses contain each BOM entry's `id`, `project`, nested `item`, optional `partID`/`allocationID`, and `requestedQuantity`. The nested `item.quantity` includes any already fulfilled quantity; `requestedQuantity` is what remains to order. Use the request's `id` for PATCH/DELETE. Sync match review remains available in the app.

## Purchase cart

Purchases are planned components, separate from inventory stock. An item can have assignments to several existing projects; their quantities must be positive and sum to no more than the item's planned quantity.

| Method | Path | Operation |
|---|---|---|
| GET | `/v1/purchases?q=...` | List/search cart items |
| POST | `/v1/purchases` | Add a cart item |
| GET | `/v1/purchases/{id}` | Get a cart item |
| PATCH | `/v1/purchases/{id}` | Update supplied fields |
| DELETE | `/v1/purchases/{id}` | Delete cart item and its planned assignments |
| POST | `/v1/purchases/receive` | Receive selected items into inventory atomically |
| GET | `/v1/projects/{name}/purchase` | List this project's purchase assignments |
| POST | `/v1/projects/{name}/purchase` | Assign an existing cart item to this project |
| PATCH | `/v1/projects/{name}/purchase/{purchaseID}` | Replace assigned quantity/designators |
| DELETE | `/v1/projects/{name}/purchase/{purchaseID}` | Remove assignment, retaining cart item |

Cart POST/PATCH accepts `part` (an object with the same editable fields as the parts API, except `stock`), `quantity` (positive integer, defaults to 1), and `assignments` (array of objects with `project`, `quantity`, and optional `designators`). `part.number` is required on create. PATCH preserves omitted fields; supplied `assignments` replaces the assignment list. Use top-level `quantity` instead of `part.stock`. Responses contain `id`, `part`, `quantity`, and `assignments`; `part.stock` in these responses also represents planned quantity, not inventory stock.

```sh
curl -X POST http://127.0.0.1:8080/v1/purchases \
  -H 'Content-Type: application/json' \
  -d '{"part":{"number":"RC0402FR-074K7L","manufacturer":"YAGEO","value":"4.7kΩ","package":"0402","lcsc":"C105871","labels":["Resistor"]},"quantity":100,"assignments":[{"project":"USB Hub","quantity":3,"designators":"R1-R3"}]}'

curl -X PATCH http://127.0.0.1:8080/v1/purchases/PURCHASE_ID \
  -H 'Content-Type: application/json' -d '{"quantity":200}'

curl -X POST http://127.0.0.1:8080/v1/projects/USB%20Hub/purchase \
  -H 'Content-Type: application/json' -d '{"purchaseID":"PURCHASE_ID","quantity":5,"designators":"R1-R5"}'

curl -X PATCH http://127.0.0.1:8080/v1/projects/USB%20Hub/purchase/PURCHASE_ID \
  -H 'Content-Type: application/json' -d '{"quantity":4}'

curl -X POST http://127.0.0.1:8080/v1/purchases/receive \
  -H 'Content-Type: application/json' -d '{"ids":["PURCHASE_ID","ANOTHER_PURCHASE_ID"]}'
```

Project purchase POST/PATCH uses replacement quantities. Editing designators recalculates quantity, taking precedence over an explicit quantity. The main cart API stores explicit assignment quantities without inferring them from designators.

Receiving adds each item's full planned quantity to PARTS, creates a new inventory part or merges with a single match by part number/LCSC (case-insensitive), and reserves its project-assigned quantities. Existing inventory metadata is retained when merging. The cart items are removed only after the stock and reservations commit. Multiple conflicting inventory matches reject the whole batch. Retrying already-received IDs returns an error, preventing duplicate stock. Responses return `receivedPartIDs` and `receivedPurchaseIDs`. Receiving requires actual delivery; adding/editing a cart item alone never changes stock.

An unfulfilled Requested BOM entry with the same project and exact designator group is linked to the received reservation. Unrelated Requested rows are preserved. Project renames update planned assignments; project deletion removes assignments while keeping cart items.
