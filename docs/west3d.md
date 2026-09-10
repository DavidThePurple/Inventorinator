# West3D

Use **West3D Search** in the Add an item editor. Search by keywords or SKU, choose a product, choose its variant, and select **Use this part**. No credentials are required.

The integration uses West3D's public Shopify storefront endpoints: `/search/suggest.json` and `/products/{handle}.js`. Search returns up to ten suggestions, not a paginated full catalog. Refine the query to find other products. Product variants are requested only when you choose a product; the integration does not download or cache the full catalog.

Imports preserve product and variant names, SKU, variant ID, brand, supplier, and product URL. Categories match existing inventory types; unmatched categories require a choice. Owned quantity and paid cost start at zero. Unavailable variants can still be imported for items already owned.

Validation: `flutter test test/west3d_test.dart`. Optional live read-only check: `dart run tool/west3d_smoke.dart` (requires network access). Live desktop requests were verified; browser cross-origin access has not been verified.
