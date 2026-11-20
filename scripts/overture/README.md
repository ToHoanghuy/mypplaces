# Overture Places → `public.poi_overture` (fallback search)

The iOS search shows your own places and Apple MapKit results first. When Apple returns too few
relevant hits, the app calls `rpc/search_pois` (migration `20261120000001_poi_overture_fallback.sql`)
and merges these results in.

## Current import
| | |
|---|---|
| Release | Overture `2026-11-18.0` (places theme) |
| Rows | 422,329 (Vietnam only) |
| Size on Supabase | table + indexes ≈ 174 MB (heap 92 MB, trigram GIN 38 MB, GiST 27 MB, PK 17 MB); whole DB ≈ 190 MB of the 500 MB free plan |
| Filters | `addresses[0].country = 'VN'`, not closed. Confidence floor by app category: FOOD / CAFE / TRAVEL ≥ 0.60, HOTEL / ENTERTAINMENT ≥ 0.70, SHOPPING / OTHER ≥ 0.77. Tier A (food & drink, shopping, lodging, arts & entertainment, cultural & historic, education, sports & recreation, geographic, airports / stations / ferries) is kept nationwide. Everything else (services, health, government…) is kept only inside the Hà Nội, TP.HCM, Đà Nẵng, Hải Phòng and Cần Thơ boxes, at ≥ 0.77. Excluded: vehicle service, fuel, parking, sport leagues / teams. Junk names are dropped (phone numbers, more digits than letters, > 120 chars). Duplicates (same unaccented name within 30 m) are merged, keeping the highest confidence. |
| Category map | Overture `taxonomy.hierarchy` → app `place_category`. Food & drink → FOOD; non-alcoholic beverage venues, coffee shops and cafés → CAFE; bars → ENTERTAINMENT; lodging → HOTEL; shopping → SHOPPING; arts & entertainment and sport facilities → ENTERTAINMENT; historic, religious, parks and travel → TRAVEL; everything else → OTHER |

## Monthly refresh (about 15 minutes, free, no keys)
1. Find the latest release id, e.g. `aws s3 ls --no-sign-request s3://overturemaps-us-west-2/release/`, or check https://docs.overturemaps.org/release/latest/.
2. Build the batches:
   `python3 -m venv .venv && .venv/bin/pip install pyarrow duckdb && .venv/bin/python scripts/overture/build_vn_pois.py --release <id> --out out/`
   This prints the stats and writes `out/batches/*.sql`, each ≤ 950 KB.
3. Load on Supabase as `postgres` (SQL editor, `psql`, or the Supabase MCP `execute_sql`):
   - `create temp table keep_ids(id uuid);`. Optional: to delete POIs that vanished, load the ids from `out/pois.csv` and run `delete from public.poi_overture where id not in (select id from keep_ids)`.
   - `drop index public.poi_overture_search_trgm;`. Bulk upserts with the GIN index in place bloat it about 2.5× and time out.
   - Run every `out/batches/NNN.sql`. They are idempotent upserts (`on conflict (id) do update`), so re-running a batch is safe.
   - `create index poi_overture_search_trgm on public.poi_overture using gin (search_norm extensions.gin_trgm_ops);`
   - `insert into public.poi_overture_imports(release,row_count,filters) values (...)`, using the values from `stats.json`.
   - `vacuum analyze public.poi_overture;`
4. Check the size with `select pg_size_pretty(pg_total_relation_size('public.poi_overture'))` and keep it ≤ ~200 MB. If a release grows, raise the confidence floors in `CONF_BY_CAT`.

## Licence and attribution
Overture Places data comes from Meta, Microsoft, PinMeTo, Krick, RenderSEO, DAC, BrightQuery, Birdeye, Uberall and OpenTravel Alliance (CDLA-Permissive-2.0), Foursquare (Apache-2.0) and AllThePlaces (CC0). Sources are listed at https://docs.overturemaps.org/attribution/ (checked 20/11/2026).
- The places theme is not OSM-derived, so ODbL share-alike does not apply to `poi_overture`. CDLA-Permissive-2.0 puts no restriction on results computed from the data. If the dataset itself is redistributed, the licence text must travel with it.
- The app shows "Dữ liệu địa điểm: Overture Maps Foundation, © OpenStreetMap contributors" under fallback results and in Hồ sơ → Giới thiệu & nguồn dữ liệu. Overture recommends citing "Overture Maps Foundation, overturemaps.org"; the OSM credit is kept as requested and also covers OSM-derived map data.

## Search function revisions

| Migration | Change |
|---|---|
| `20261120000001_poi_overture_fallback` | table, indexes, RLS, `search_pois` v1 |
| `20261120000002_search_pois_coverage` | +0.15 × query-word coverage (whole words in name + address) so "Ốc Oanh Vĩnh Khánh" searched from Hà Nội still ranks Ốc Oanh (Q4) first |
| `20261120000003_search_pois_short_query_guard` | normalized query ≥ 3 chars; queries < 6 chars with a location only look within ±0.25° (~28 km); ≤ 10 000 candidates before scoring. Live worst case went from 14 s ("ph") to ~1 s ("nhà hàng") |

Live timings after v3 (Hà Nội centre, 10 results): "phở" 957 ms, "phở bò" 399 ms, "nhà hàng" 1054 ms, "cafe" 380 ms, "Hồ Hoàn Kiếm" 468 ms, "Ốc Oanh Vĩnh Khánh" 110 ms.
