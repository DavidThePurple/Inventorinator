# Core workflow completion pass

- Supplier previews reuse the downloaded image (up to 1024px), preserve aspect ratio, and open a local zoom viewer. Cache and concurrency limits remain unchanged.
- Sync conflict review lives in **Reports and change log → Sync conflicts**. Both merge paths retain local and remote values. Unresolved records remain in the outbox while other records sync. Field baselines distinguish a remote change from an echo of our earlier save. v25 conditional writes reject a server change that occurs after the client reads it. Choosing the remote value refuses to overwrite a newer local edit.
- **Reports and change log → Reports / printable lists** provides searchable inventory, date-filtered spool use/waste and recorded movements, shopping lists and expanded kit shortage lists. Each can be previewed, saved, shared or printed as a PDF, generated locally in a worker isolate with a bundled font. Report rendering is paged at 50 rows; PDFs contain all matching rows.
- Inventory reports describe current records, not reconstructed historical valuations. The movement report is limited to retained audit entries (currently at most 2,000). Costs are the recorded values, not supplier quotes or a currency-normalized valuation. Kit shortages subtract reservations and aggregate nested kit requirements.
- Custom roles require server v25; see role-builder.md and server-update-v25.md. Server migrations are prepared and tested locally, not applied to the user's server.

Remaining work from the broader audit: cross-device/portable item drafts, complete spool transfers/refills/printer attribution, exhaustive supplier catalog pagination where available, and historical valuation reconstruction. These are distinct from this completion pass.
