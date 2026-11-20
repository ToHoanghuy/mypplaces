#!/usr/bin/env python3
"""Build the Vietnam POI catalogue (public.poi_overture) from an Overture Maps places release.

Usage:  python build_vn_pois.py --release 2026-11-18.0 --out out/
Needs:  pip install pyarrow duckdb   (reads the public S3 bucket anonymously; no key, no account)
Writes: out/pois.csv            (id,name,category,address,latitude,longitude,confidence)
        out/batches/NNN.sql     (INSERT batches ≤ ~900 KB each, for the Supabase SQL connector/psql)
        out/stats.json
"""
import argparse, json, math, os, re, unicodedata, csv
import duckdb, pyarrow.dataset as ds, pyarrow.fs as pfs

CONF_MIN = 0.60      # scan floor
# Per app-category floor inside tier A: lower for what users search most (food, cafés, sights).
CONF_BY_CAT = {"FOOD": 0.60, "CAFE": 0.60, "TRAVEL": 0.60, "HOTEL": 0.70, "ENTERTAINMENT": 0.70, "SHOPPING": 0.77, "OTHER": 0.77}
CONF_MIN_B = 0.77    # tier B (services etc., big cities only)
# Tier A: kept nationwide.  Tier B: other categories, kept only inside the big-city boxes.
TIER_A = {"food_and_drink", "shopping", "lodging", "arts_and_entertainment", "cultural_and_historic",
          "education", "sports_and_recreation", "geographic_entities"}
TIER_A_L2 = {"air_transport_facility_or_service", "ground_transport_facility_or_service",
             "water_transport_facility_or_service"}
CITY_BOXES = {  # (lon_min, lat_min, lon_max, lat_max), generous metro areas
    "Ha Noi": (105.70, 20.90, 106.00, 21.15), "TP.HCM": (106.55, 10.68, 106.85, 10.90),
    "Da Nang": (108.10, 15.95, 108.30, 16.13), "Hai Phong": (106.60, 20.78, 106.75, 20.90),
    "Can Tho": (105.70, 9.98, 105.82, 10.08)}
EXCLUDE_L2 = {"vehicle_service", "fueling_station", "parking", "sport_league", "sport_team"}

def app_category(h1, h2, basic):
    h1 = h1 or ""; h2 = h2 or ""; basic = basic or ""
    if h1 == "food_and_drink":
        if h2 == "non_alcoholic_beverage_venue" or basic in ("coffee_shop", "cafe", "tea_room"): return "CAFE"
        if h2 == "alcoholic_beverage_venue": return "ENTERTAINMENT"
        return "FOOD"
    if basic in ("coffee_shop", "cafe"): return "CAFE"
    if h1 == "lodging": return "HOTEL"
    if h1 == "shopping": return "SHOPPING"
    if h1 == "arts_and_entertainment" or h2 in ("sport_or_fitness_facility", "sport_or_recreation_club"): return "ENTERTAINMENT"
    if h1 in ("cultural_and_historic", "geographic_entities") or h2 in ("park", "recreational_trail_or_path", "travel_service"): return "TRAVEL"
    return "OTHER"

PHONE = re.compile(r"(\+?84|0)[\s.\-]?\d{2,3}[\s.\-]?\d{3}[\s.\-]?\d{3,4}")
def clean_name(n):
    if not n: return None
    n = unicodedata.normalize("NFKC", n)          # 𝟎𝟗𝟔 -> 096, full-width -> ascii
    n = re.sub(r"\s+", " ", n).strip()
    if PHONE.search(n): return None                # names that are adverts with phone numbers
    digits = sum(c.isdigit() for c in n); letters = sum(c.isalpha() for c in n)
    if letters < 2 or digits > letters: return None
    if len(n) > 120: return None
    return n

def norm(n):
    s = unicodedata.normalize("NFD", n.replace("Đ", "D").replace("đ", "d"))
    s = "".join(c for c in s if unicodedata.category(c) != "Mn").lower()
    return re.sub(r"[\W_]+", " ", s).strip()

def short_addr(addresses):
    if not addresses: return None
    a = addresses[0]
    parts = [p.strip() for p in (a.get("freeform"), a.get("locality")) if p and p.strip()]
    out = []
    for p in parts:
        if not any(p.lower() in o.lower() for o in out): out.append(p)
    s = ", ".join(out)
    return s[:200] or None

def in_city(x, y):
    return any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in CITY_BOXES.values())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--release", required=True); ap.add_argument("--out", default="out")
    ap.add_argument("--conf", type=float, default=CONF_MIN); ap.add_argument("--conf-b", type=float, default=CONF_MIN_B); ap.add_argument("--batch-bytes", type=int, default=900_000)
    a = ap.parse_args(); os.makedirs(f"{a.out}/batches", exist_ok=True)
    fs = pfs.S3FileSystem(anonymous=True, region="us-west-2")
    d = ds.dataset(f"overturemaps-us-west-2/release/{a.release}/theme=places/type=place/", filesystem=fs, format="parquet")
    B = lambda k: ds.field("bbox", k)
    flt = (B("xmin") > 102.1) & (B("xmax") < 117.9) & (B("ymin") > 6.0) & (B("ymax") < 23.4) & (ds.field("confidence") >= a.conf)
    t = d.to_table(filter=flt, columns={"id": ds.field("id"), "name": ds.field("names", "primary"),
        "basic": ds.field("basic_category"), "hier": ds.field("taxonomy", "hierarchy"), "conf": ds.field("confidence"),
        "status": ds.field("operating_status"), "addresses": ds.field("addresses"), "x": B("xmin"), "y": B("ymin")})
    stats = {"release": a.release, "conf_min": a.conf, "conf_min_tier_b": a.conf_b, "scanned": t.num_rows}
    rows = []; drop = {"not_vn": 0, "closed": 0, "junk_name": 0, "tier_b_outside_city": 0, "excluded_cat": 0}
    for r in t.to_pylist():
        addrs = r["addresses"] or []
        if not addrs or addrs[0].get("country") != "VN": drop["not_vn"] += 1; continue
        if r["status"] in ("permanently_closed", "temporarily_closed"): drop["closed"] += 1; continue
        h = r["hier"] or []; h1 = h[0] if h else None; h2 = h[1] if len(h) > 1 else None
        if h2 in EXCLUDE_L2: drop["excluded_cat"] += 1; continue
        tier_a = h1 in TIER_A or h2 in TIER_A_L2
        if not tier_a and not in_city(r["x"], r["y"]): drop["tier_b_outside_city"] += 1; continue
        if not tier_a and r["conf"] < a.conf_b: drop["tier_b_low_conf"] = drop.get("tier_b_low_conf", 0) + 1; continue
        cat = app_category(h1, h2, r["basic"])
        if r["conf"] < max(a.conf, CONF_BY_CAT[cat]): drop["below_category_conf"] = drop.get("below_category_conf", 0) + 1; continue
        n = clean_name(r["name"])
        if not n: drop["junk_name"] += 1; continue
        rows.append(dict(id=r["id"], name=n, category=cat, address=short_addr(addrs),
                         latitude=round(r["y"], 6), longitude=round(r["x"], 6), confidence=round(r["conf"], 3), _n=norm(n)))
    # de-duplicate: same normalised name within ~30 m -> keep the highest confidence
    rows.sort(key=lambda r: -r["confidence"]); kept = []; seen = {}
    for r in rows:
        key = r["_n"]; cell = (round(r["latitude"] / 0.0003), round(r["longitude"] / 0.0003))
        dup = False
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                for o in seen.get((key, cell[0] + dy, cell[1] + dx), ()):
                    dlat = (o["latitude"] - r["latitude"]) * 111_000
                    dlon = (o["longitude"] - r["longitude"]) * 111_000 * math.cos(math.radians(r["latitude"]))
                    if dlat * dlat + dlon * dlon <= 30 * 30: dup = True; break
                if dup: break
            if dup: break
        if dup: continue
        seen.setdefault((key, *cell), []).append(r); kept.append(r)
    drop["duplicate_30m"] = len(rows) - len(kept); stats["dropped"] = drop; stats["kept"] = len(kept)
    stats["by_category"] = {}
    for r in kept: stats["by_category"][r["category"]] = stats["by_category"].get(r["category"], 0) + 1
    cols = ["id", "name", "category", "address", "latitude", "longitude", "confidence"]
    with open(f"{a.out}/pois.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(cols); [w.writerow([r[c] for c in cols]) for r in kept]
    q = lambda s: "null" if s is None else "'" + s.replace("'", "''") + "'"
    head = "insert into public.poi_overture (id,name,category,address,latitude,longitude,confidence) values\n"
    tail = "\non conflict (id) do update set name=excluded.name, category=excluded.category, address=excluded.address, latitude=excluded.latitude, longitude=excluded.longitude, confidence=excluded.confidence;\n"
    i = 0; buf = []; size = 0
    def flush():
        nonlocal i, buf, size
        if buf:
            open(f"{a.out}/batches/{i:03d}.sql", "w").write(head + ",\n".join(buf) + tail); i += 1; buf = []; size = 0
    for r in kept:
        v = f"('{r['id']}',{q(r['name'])},'{r['category']}',{q(r['address'])},{r['latitude']},{r['longitude']},{r['confidence']})"
        if size + len(v.encode()) > a.batch_bytes: flush()
        buf.append(v); size += len(v.encode()) + 2
    flush(); stats["batches"] = i
    stats["filters"] = (f"Overture {a.release} places; country=VN; open; confidence floor per category {CONF_BY_CAT} (tier A) / >={a.conf_b} (tier B); tier A ({', '.join(sorted(TIER_A))} + transport hubs) nationwide; "
                        f"other categories only in {', '.join(CITY_BOXES)}; excluded {', '.join(sorted(EXCLUDE_L2))}; junk names (phones, digit-heavy) dropped; "
                        "duplicates (same normalised name within 30 m) merged")
    json.dump(stats, open(f"{a.out}/stats.json", "w"), ensure_ascii=False, indent=1); print(json.dumps(stats, ensure_ascii=False, indent=1))

if __name__ == "__main__":
    main()
