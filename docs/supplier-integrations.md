# Supplier integration candidates

Checked 2026-09-10. This tracks product search/import sources, not printer control or ordering. Implemented suppliers are listed below; entries marked as candidates are not enabled in the app.

| Supplier | Product-data access | Access / limitations | Status and next step |
| --- | --- | --- | --- |
| DigiKey | Product Information V4 | User's subscribed developer app credentials | Implemented. |
| Mouser | Search API | User's Search API key | Implemented. |
| West3D | Public Shopify search suggestions and product JSON | No credentials; suggestions limited to ten, variant detail fetched on selection | Implemented; see [West3D](west3d.md). |
| **LDO Motion** | Public Shopify storefront search and product/variant JSON | No credentials; storefront endpoints, not a separately published LDO partner API | **Implemented.** Search, select a variant, and import details/photos. Uses the shared storefront flow with LDO-specific identity and domain validation. |
| **BIQU / BIGTREETECH** | Public storefront search and product/variant JSON | No credentials; `biqu.equipment` | **Implemented.** Keyword search, variants, SKU, photo, and BIQU supplier identity. |
| **E3D** | Public storefront search and product/variant JSON | No credentials; `e3d-online.com` | **Implemented.** Keyword search, variants, SKU, and photo import. |
| **Polymaker** | Public storefront search and product/variant JSON | No credentials; US store at `us.polymaker.com` | **Implemented.** Color/spool variants retain their variant names, SKU, image, and links. |
| **Printed Solid** | Public storefront search and product/variant JSON | No credentials; `www.printedsolid.com` | **Implemented.** Keyword search, variants, SKU, and photo import. |
| **Slice Engineering** | Public storefront search and product/variant JSON | No credentials; `www.sliceengineering.com` | **Implemented.** Keyword search, variants, SKU, and photo import. |
| **Fabreeko** | Public storefront search and product/variant JSON | No credentials; `www.fabreeko.com` | **Implemented.** Keyword search, variants, SKU, photo, and supplier links. |
| **The Pi Hut** | Public storefront search and product/variant JSON | No credentials; `thepihut.com` | **Implemented.** Keyword search, variants, SKU, photo, and supplier links. |
| **Fillamentum** | Public storefront search and product/variant JSON | No credentials; `shop.fillamentum.com` | **Implemented.** Keyword search, selected-product variants, SKU, photos, and supplier links. |
| **Sovol** | Public storefront search and product/variant JSON | No credentials; `www.sovol3d.com` | **Implemented.** Keyword search, selected-product variants, SKU, photos, and supplier links. |
| **Siraya Tech** | Public storefront search and product/variant JSON | No credentials; `siraya.tech` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Micro Swiss** | Public storefront search and product/variant JSON | No credentials; `store.micro-swiss.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Atomic Filament** | Public storefront search and product/variant JSON | No credentials; `atomicfilament.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Matter3D** | Public storefront search and product/variant JSON | No credentials; `www.matter3d.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Mandala Rose Works** | Public storefront search and product/variant JSON | No credentials; `mandalaroseworks.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Ember Prototypes** | Shopify store linked from its official Squarespace product page | No credentials; `emberprototypes.myshopify.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Protopasta** | Public storefront search and product/variant JSON | No credentials; `proto-pasta.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **FYSETC** | Public storefront search and product/variant JSON | No credentials; `www.fysetc.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **PETG USA** | Public storefront search and product/variant JSON | No credentials; `petgusa.com` | **Implemented.** Keyword search, variants, photos, and supplier links. Variant ID remains available when the supplier omits SKU. |
| **SainSmart / Genmitsu** | Public storefront search and product/variant JSON | No credentials; `www.sainsmart.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **3D Printing Canada** | Public storefront search and product/variant JSON | No credentials; `3dprintingcanada.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **M5Stack** | Public storefront search and product/variant JSON | No credentials; `shop.m5stack.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **RAKwireless** | Public storefront search and product/variant JSON | No credentials; `store.rakwireless.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **DFH** | Public storefront search and product/variant JSON | No credentials; `checkout.dfh.fm` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Overture** | Public storefront search and product/variant JSON | No credentials; `overture3d.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Pimoroni** | Public storefront search and product/variant JSON | No credentials; `shop.pimoroni.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Arduino** | Public storefront search and product/variant JSON | No credentials; `store.arduino.cc` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Inventables** | Public storefront search and product/variant JSON | No credentials; `www.inventables.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Push Plastic** | Public storefront search and product/variant JSON | No credentials; `www.pushplastic.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **VOXELPLA** | Public storefront search and product/variant JSON | No credentials; `voxelpla.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **3D-Fuel** | Public storefront search and product/variant JSON | No credentials; `www.3dfuel.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **American Filament** | Public storefront search and product/variant JSON | No credentials; `www.americanfilament.us` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **SEQURE** | Public storefront search and product/variant JSON | No credentials; `sequremall.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Alpenglow Industries** | Public storefront search and product/variant JSON | No credentials; `alpenglowindustries.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Bantam Tools** | Public storefront search and product/variant JSON | No credentials; `bantamtools.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **DREMC** | Public storefront search and product/variant JSON | No credentials; `store.dremc.com.au` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Cookiecad** | Public storefront search and product/variant JSON | No credentials; `www.cookiecad.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Revopoint** | Public storefront search and product/variant JSON | No credentials; `www.revopoint3d.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **TinyCircuits** | Public storefront search and product/variant JSON | No credentials; `tinycircuits.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **HackerBoxes** | Public storefront search and product/variant JSON | No credentials; `hackerboxes.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Elektor** | Public storefront search and product/variant JSON | No credentials; `www.elektor.com` | **Implemented.** Keyword search, variants, SKU, photos, and supplier links. |
| **Adafruit** | Official Products API catalog, searched locally in SQLite | No credentials; maximum five requests/minute; no image hotlinking | **Implemented: keyword, part-number, and product-link search.** First keyword search downloads the catalog once; subsequent searches and 12-item pages are local. Manual refresh uses the shared cooldown. |
| **Newark / Farnell / element14** | Official Product Search API: keywords, supplier part number, manufacturer part number | API key; regional store selection; offset/limit pagination. Special contract pricing needs additional credentials. | **Good documented search candidate.** Documentation checked; authenticated requests not tested. |
| **TME** | Official v2 product search/details, parameters, images, stock | OAuth 2.0; paginated search | **Good documented candidate.** Documentation checked; authenticated requests not tested. |
| **Pololu** | Official v2 product/catalog API with pagination and specifications | Request API key by email; HTTP Basic authentication. API access does not grant redistribution rights to copyrighted content. | **Possible, access request needed.** Documentation checked; authenticated requests not tested. |
| **Prusa / Prusament shop** | No documented public shop catalog API found in this check | PrusaLink/Connect documentation concerns printer services, not the shop product catalog | **Unconfirmed.** Ask Prusa about a product feed/API; do not mistake printer API access for product-search access. |
| McMaster-Carr | Previously discussed | User shelved this integration | On hold; not revisited in this check. |

## Sources and live checks

- PETG USA passed the live app-client check on 2026-09-10: `matte` returned ten suggestions and one variant for the selected product. The sampled SKU is absent; import tests verify preserving the variant ID and link without inventing a part number. Repeat with `dart run tool/storefronts_smoke.dart petgusa`.


- Additional storefronts checked 2026-09-10: [Protopasta](https://proto-pasta.com/) `htpla` search returned Black Opaque HTPLA with four variants and an image; [FYSETC](https://www.fysetc.com/) `spider` returned a Spider V3.0 H7 board with one variant and an image. Both returned public search/product JSON without credentials; both are implemented. Repeat the app-client check with `dart run tool/storefronts_smoke.dart protopasta fysetc`.


- [Ember Prototypes CXC page](https://www.emberprototypes.com/products/cxc) links to `https://emberprototypes.myshopify.com/products/emb02-cxc`. On 2026-09-10 that store returned one `cxc` suggestion and one variant with an image URL. Ember is enabled in the picker; `dart run tool/storefronts_smoke.dart ember` verifies the actual app client.


- Atomic Filament, Matter3D, and Mandala Rose Works passed live app-client checks on 2026-09-10: ten suggestions each, with 1, 86, and 3 variants respectively for the selected products. Repeat with `dart run tool/storefronts_smoke.dart atomic matter3d mandala`.


- Siraya Tech and Micro Swiss passed live app-client checks on 2026-09-10: `resin` returned ten suggestions and three variants for the selected Siraya Tech product; `nozzle` returned ten suggestions and two variants for the selected Micro Swiss product. Repeat with `dart run tool/storefronts_smoke.dart siraya microswiss`. Both use the existing bounded search and on-selection detail/photo flow.


- Fillamentum and Sovol passed live app-client checks on 2026-09-10: `pla` returned ten suggestions and two variants for the selected Fillamentum product; `nozzle` returned ten suggestions and 26 variants for the selected Sovol product. Run `dart run tool/storefronts_smoke.dart fillamentum sovol` to repeat these bounded requests.


- Fabreeko and The Pi Hut passed live app-client checks on 2026-09-10: `voron` returned ten suggestions and 48 variants for the selected Fabreeko product; `sensor` returned ten suggestions and one variant for the selected Pi Hut product. Run `dart run tool/storefronts_smoke.dart fabreeko pihut` to repeat only these two suppliers. Both share bounded search, on-selection variant retrieval, and cached photos.
- Initial storefront probes: [Fillamentum](https://shop.fillamentum.com/) `pla` returned two requested suggestions and two variants; [Sovol](https://www.sovol3d.com/) `nozzle` returned two requested suggestions and 26 variants. Public storefront availability is not a dedicated API support commitment.


- The five additional storefronts use the same bounded ten-suggestion search and on-selection variant retrieval as West3D/LDO. All passed live client checks on 2026-09-10: BIQU `skr` (3 variants), E3D `revo` (5), Polymaker `pla` (32), Printed Solid `jessie` (1), Slice `mosquito` (3). These are counts for the first matched product, not catalog totals. Verify with `dart run tool/storefronts_smoke.dart`; this makes two read-only requests per store. No full-catalog fetch or product-photo prefetch is added. These public storefront endpoints are not dedicated partner API commitments.
- Official stores: [BIQU](https://biqu.equipment/), [E3D](https://e3d-online.com/), [Polymaker US](https://us.polymaker.com/), [Printed Solid](https://www.printedsolid.com/), [Slice Engineering](https://www.sliceengineering.com/).
- LDO [official store](https://store.ldomotion.com/) and [manufacturer website](https://ldomotion.com/).
  - Live `GET https://store.ldomotion.com/products.json?limit=1`: one product returned.
  - Live `GET https://store.ldomotion.com/search/suggest.json?q=nitehawk&resources[type]=product&resources[limit]=2`: two suggestions returned.
  - Live `GET https://store.ldomotion.com/products/ldo-nitehawk-hexa-6-1-port-usb-hub-adapter-for-multi-toolhead-3d-printers.js`: one variant, SKU `LDO-NH-HEXA`.
  - This establishes current technical availability, not a long-term LDO API support commitment. Browser cross-origin support has not been tested.
- [Adafruit Products API and usage rules](https://www.adafruit.com/products_api). Live HTTPS `/api/products` and `/api/product/998` returned JSON without authentication.
- [element14 Product Search API](https://partner.element14.com/docs/Product_Search_API_REST__Description).
- [TME v2 API](https://api-doc.tme.eu/v2).
- [Pololu official API repository](https://github.com/pololu/pololu-api).
- [PrusaLink official API specification](https://github.com/prusa3d/Prusa-Link-Web/blob/master/spec/openapi.yaml). No public shop catalog documentation located; absence of documentation in this search does not prove no private or partner feed exists.

## UI

The Add an item editor groups implemented integrations in **Search suppliers**. Candidates do not appear as nonfunctional menu entries. Adafruit accepts keywords, part numbers, numeric product IDs, and product links. Unmatched categories require an explicit choice; imports never invent owned stock or paid cost.

Adafruit's first keyword search downloads `/api/products` once into a separate `adafruit-catalog.sqlite3` beside the local inventory database. A background isolate streams one product at a time into SQLite; searches filter/count on disk and load only 12 results per page. The catalog contains metadata and image URLs, not downloaded product photos. It is not inventory and is not synchronized to the workshop server. It remains searchable offline and during cooldown. The update date is shown; **Refresh catalog** explicitly refreshes it. Failed or malformed updates roll back atomically. Downloads are capped at 32 MiB and individual records at 512 KiB. Product ID lookup remains a fallback when a specific ID is absent from the saved catalog.

Adafruit cooldown is shared across dialogs and saved locally as `adafruit_next_request` when a database is available. Every attempted request consumes its slot, including failures. Up to 32 successful product lookups are cached in memory for 30 minutes and remain usable during cooldown. HTTP 429 honors Retry-After (seconds or HTTP date), with a one-minute fallback. The visible countdown/progress is a local timer, not API polling; reopening or restarting does not reset a saved cooldown. This gate is per app/device, not a quota shared between independent devices. Published Adafruit content-use rules still apply; imported images are downloaded and stored, not remotely embedded.

## Product images

DigiKey (`PhotoUrl`), Mouser (`ImagePath`), and West3D (product/variant image) use image URLs from existing responses: no additional catalog or media API call is needed. West3D prefers the selected variant's image and falls back to the product image.

Previews start when their cards enter the viewport. CDN downloads are deduplicated, limited to two at once, and share a 10-minute cache capped at 48 entries / 12 MiB. Failures are cached too, without automatic retries. Each download has a 15-second deadline, a 6 MiB limit, and a 16-megapixel decode limit. URLs must use HTTPS; requests carry no API credentials and do not follow redirects.

Images are resized to at most 1024 pixels with separate 256-pixel thumbnails. Selecting a part prioritizes its image request and waits for it before returning to the editor; a failed image still allows importing details. The selected image and thumbnail become ordinary local item data, including drafts and the existing storage/sync path. An existing photo or thumbnail is preserved. The in-memory preview cache is temporary; saved item images remain available offline.

- SainSmart / Genmitsu and 3D Printing Canada passed live app-client checks on 2026-09-10: `end mill` returned ten suggestions and five variants for the selected SainSmart product; `nozzle` returned ten suggestions and one variant for the selected Canadian product. Repeat with `dart run tool/storefronts_smoke.dart sainsmart printingcanada`. Both use bounded search and fetch product details only on selection.

- M5Stack, RAKwireless, DFH, Overture, and Pimoroni passed live app-client checks on 2026-09-10: ten suggestions each; selected-product variant counts 1, 48, 16, 24, and 1 respectively. Repeat with `dart run tool/storefronts_smoke.dart m5stack rakwireless dfh overture pimoroni`. DFH uses its Shopify checkout storefront at `checkout.dfh.fm`. All use bounded search and selected-product details/photos, without a full catalog download.

## B&H Photo investigation (2026-09-10)

Not enabled. No documented public product-catalog/search API was found. A direct
request to `https://www.bhphotovideo.com/c/search?q=arduino&sts=ma` returned HTTP 403.
The [official affiliate program](https://www.bhphotovideo.com/c/find/shared/affiliates.jsp)
accepts applications, but this does not establish catalog API/feed access.
The [official EZ-Link documentation](https://affportal.bhphoto.com/static/bhphoto_chrome_extension_privacy.html)
describes an affiliate API for generating tracking links from URLs or keywords,
not a structured product search API. The next step is to ask B&H whether approved
partners can obtain a product feed/API suitable for desktop inventory imports,
including images and local caching. No signup, outreach, or third-party scraping
service was used. Catalog availability behind partner access remains unverified.

- Arduino, Inventables, Push Plastic, VOXELPLA, 3D-Fuel, and American Filament passed
  live app-client checks on 2026-09-10: ten suggestions each; selected-product
  variant counts 1, 2, 29, 2, 3, and 3 respectively. Repeat with
  `dart run tool/storefronts_smoke.dart arduino inventables pushplastic voxelpla fuel3d americanfilament`.

- SEQURE, Alpenglow Industries, Bantam Tools, DREMC, Cookiecad, and Revopoint passed live app-client checks on 2026-09-10: ten suggestions each; selected-product variant counts 20, 18, 6, 4, 1, and 1 respectively. Repeat with `dart run tool/storefronts_smoke.dart sequre alpenglow bantam dremc cookiecad revopoint`. Uses the same bounded requests and selected-product image flow.

- TinyCircuits, HackerBoxes and Elektor passed live app-client search/variant checks on 2026-09-10. Repeat with `dart run tool/storefronts_smoke.dart tinycircuits hackerboxes elektor`.
