# LCSC Purchase Chrome extension

1. Rebuild and run BOM Inventory with this checkout so the API supports image imports.
2. Start the app's local API (default `127.0.0.1:8080`).
3. Open Chrome's Extensions page (`chrome://extensions`), enable **Developer mode**, choose **Load unpacked**, and select this `chrome-extension` folder.
4. Open the extension, expand **Local API settings**, enter the HTTP address (for example `http://127.0.0.1`) and port, then choose **Save & load projects**. Allow access to that host when prompted.
5. Open an LCSC product detail page and click **Read current LCSC product**. Review or correct the extracted fields, image URL, and datasheet URL.
6. Enter the purchase quantity, check the desired projects, and enter the quantity allocated to each. Their sum must not exceed the purchase quantity. Unallocated purchases are allowed.
7. Click **Add to Purchase**, allow access to the image host, and keep the popup open until success appears.

The extension reuses the application's icons. It reads only the active page when invoked and requests API/image host access as needed. Settings are stored locally in Chrome. Photos are downloaded, resized to JPEG (up to 800 pixels), and uploaded with the purchase; datasheets remain links. Image errors stop the import so they are not silently omitted. Clear the image URL explicitly to import without a photo.

LCSC layouts vary; the scraper uses Product JSON-LD, metadata, and visible specification labels. Missing fields remain editable. Review the datasheet link and part number before saving. Closing the popup interrupts work; after a connection error during submission, check the app before retrying to avoid duplicates. The app must remain running and reachable. The local API has no authentication; use a trusted local interface.

Implementation follows Chrome's [activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) and [optional host permissions](https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions) model.
