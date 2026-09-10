# DigiKey integration groundwork

Open **Remote Settings → DigiKey**, enter the client ID and secret for your
DigiKey developer application subscribed to Product Information V4, and click
Save. Then use **Add → Search DigiKey**, select a packaging variant, and
review the item before saving. This integration does not depend on Supabase.

The first implementation uses the US catalog, English and USD. It supports
production and sandbox endpoints, paginated keyword search, OAuth token
reuse, and explicit authentication/rate-limit/network errors. Live responses
have not yet been verified with a subscribed developer account.

Credentials persist in device-private SQLite preferences, scoped to the server and
workspace, and are excluded from portable inventory exports. Owners also retain
a remote copy through owner-only RPCs (schema 23). Offline saves remain local
with a pending remote update; opening Remote Settings or pressing Sync retries.
Remote Settings restores the workspace copy on another owner device. Access
tokens remain transient. Secrets are not encrypted at rest by the application;
local file permissions and server access controls protect the stored copies.
There is no shared application secret bundled with the app. A future distributed web build should use an authenticated server
adapter for confidential credentials and review DigiKey's browser/CORS and
application-distribution requirements. The Dart data/client layer is separate
from the Flutter UI; this is not a claim that Flutter cannot build for web.

## Import semantics

- Each selectable result represents a DigiKey SKU and packaging variation.
- Manufacturer part number, description, source URL, datasheet URL, packaging,
  minimum order and standard package quantity are retained as namespaced
  `supplier.digikey.*` metadata in the existing item custom-field map.
- Supplier stock and purchasing minimums are not owned inventory. New items
  start with quantity zero; the user enters their actual quantity.
- Quotes are displayed only when the selected variation provides a one-unit
  price and a response currency. Quotes are not copied into actual cost.
- A SKU is not assumed to be a barcode. It does not overwrite a scanned GTIN.
  Selecting a fresh DigiKey item clears the draft barcode for review.
- Existing matching SKUs trigger a warning. Saving creates a separate record;
  no automatic merge or stock increment is performed.
- Editing an existing item retains supplier metadata even for built-in types.
- Images, account pricing, purchasing, automatic stock refresh, and bulk/BOM
  imports are not implemented in this first slice.

## Sources checked

- https://developer.digikey.com/documentation
- https://developer.digikey.com/products/product-information-v4/productsearch/keywordsearch
- https://developer.digikey.com/node/2357/oas-download

The official V4 schema defines the OAuth-compatible keyword endpoint,
`Products`, `ProductVariations`, package-specific SKUs/pricing/availability,
and `SearchLocaleUsed`. Tests use synthetic responses conforming to those
fields; passing tests is not live API verification.
