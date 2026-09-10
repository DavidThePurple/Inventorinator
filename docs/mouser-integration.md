# Mouser integration

Remote Settings → Mouser → enter your **Search API key** → Save.
Use Add item → Search Mouser to search by keyword or manufacturer part number,
select a result and review the new inventory item. Quantity and actual cost
start at zero. Duplicate supplier SKUs produce a warning; imports do not merge
stock automatically. Descriptions, source links, packaging and MOQ are retained.
Price strings are not interpreted as actual purchase costs.

Credentials persist in private local preferences and are excluded from portable
inventory exports. Owners can save/restore a remote copy with schema 24.
Offline saves remain pending until Remote Settings is reopened or Sync is used.
Application-level encryption at rest is not implemented; file permissions and
owner-only server access controls protect the stored key.
The header indicator appears only for a configured key and reflects searches,
not whether the settings were saved. Search errors never display request URLs
because Mouser requires the key in the query string.

Uses POST /api/v1/search/keyword with 20 results per page. The Search API signup
page documents 30 calls/minute and 1,000/day; quota failures are surfaced without
automatic retries. No cart or ordering APIs are used. Live account testing awaits
a user-supplied key; automated tests use synthetic official-schema responses.

Sources: https://www.mouser.com/en/api-search/ and https://api.mouser.com/api/docs/V1
