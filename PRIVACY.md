# Privacy

Inventorinator has no first-party analytics or advertising. Inventory is kept
in a local SQLite database unless the user enables synchronization.

When synchronization is enabled, the complete workshop state—including item
images, custom Type icons, and captured label images—is sent to the hosted or
self-hosted Supabase instance chosen by the user. Authentication and refresh
tokens are stored on the device so it can reconnect. A plain HTTP server address is supported for
private LAN installations, but it is not encrypted; use HTTPS across untrusted
networks.

Barcode and QR recognition is performed on the device. Android label OCR uses
Google ML Kit's on-device text-recognition SDK. Linux label OCR uses the bundled
Tesseract data and the compatible system libraries. Importing a product URL
contacts that website directly. **Search web** opens the selected search
provider in the device's browser, subject to that provider's privacy policy.
Using **Search FilamentColors.xyz** sends the entered brand, material, and
color search text directly to FilamentColors.xyz. Results are cached in the
local SQLite database for seven days; stale cached results may be used when the
service is unavailable. Blank searches are blocked, duplicate requests are
collapsed, and client-side request limits prevent rapid repeated API traffic.

Deleting the local database removes the local inventory, sync configuration,
and preferences. It does not delete data already stored by a configured cloud
provider; use that provider's administration tools or delete the shared
workspace separately.
