"""01_generate_events.sql と同じ架空データを、BigQuery なしで生成する（NDJSON）。
乱数は FARM_FINGERPRINT（pyfarmhash の fingerprint64 を符号付きにしたもの。BigQuery と一致）。
使い方: pip install pyfarmhash && python generate_ndjson.py > events_all.ndjson
データはすべて架空。実在のストア・顧客のデータではない。
"""
import json, datetime, sys
from decimal import Decimal, ROUND_HALF_UP
import farmhash


def fp(s):
    v = farmhash.fingerprint64(s)
    return v - (1 << 64) if v >= 1 << 63 else v


def md(tag, d, i, n):
    return abs(fp(f"{tag}{d}-{i}")) % n


def rows():
    out = []
    for d in range(30):
        date = datetime.date(2026, 9, 1) + datetime.timedelta(days=d)
        day_us = int(datetime.datetime(date.year, date.month, date.day, tzinfo=datetime.timezone.utc).timestamp()) * 1_000_000
        for i in range(1, 161):
            if md("n", d, i, 100) >= 85:
                continue
            uid = 1 + md("u", d, i, 2500)
            gsid = 1700000000 + md("g", d, i, 200)
            rc, rv, ra, rb, rp = (md(t, d, i, 100) for t in "cvabp")
            sku = md("k", d, i, 12)
            qty = md("q", d, i, 2) + 1
            sec = md("t", d, i, 50000)
            if rc < 20:   src, med, camp, p_atc = "google", "cpc", "brand_search", 30
            elif rc < 50: src, med, camp, p_atc = "google", "organic", "(organic)", 20
            elif rc < 75: src, med, camp, p_atc = "(direct)", "(none)", "(direct)", 45
            elif rc < 85: src, med, camp, p_atc = "yahoo", "cpc", "ly_ads_sale", 15
            else:         src, med, camp, p_atc = "newsletter", "email", "mail_autumn", 40
            price = 1000 + sku * 700
            stages = [(0, "session_start"), (1, "page_view")]
            if rv < 80: stages.append((2, "view_item"))
            if rv < 80 and ra < p_atc: stages.append((3, "add_to_cart"))
            if rv < 80 and ra < p_atc and rb < 60: stages.append((4, "begin_checkout"))
            if rv < 80 and ra < p_atc and rb < 60 and rp < 70: stages.append((5, "purchase"))
            txn = f"T{d:02d}-{i:03d}"
            for ord_, name in stages:
                ts = day_us + (sec + ord_ * 40) * 1_000_000
                page = "https://shop.example.invalid/" + (f"item/SKU-{sku:02d}" if ord_ >= 2 else "") + f"?utm_source={src}"
                manual = None
                if med in ("cpc", "email"):
                    manual = {"campaign_id": None, "campaign_name": camp, "source": src, "medium": med,
                              "term": None, "content": None, "source_platform": None}
                grp = {"cpc": "Paid Search", "organic": "Organic Search", "email": "Email"}.get(med, "Direct")
                if name == "purchase":
                    usd = float((Decimal(price * qty) / Decimal(150)).quantize(Decimal("0.01"), ROUND_HALF_UP))
                    eco = {"transaction_id": None if i % 37 == 0 else txn, "purchase_revenue": float(price * qty),
                           "purchase_revenue_in_usd": usd, "total_item_quantity": qty}
                else:
                    eco = None
                items = ([{"item_id": f"SKU-{sku:02d}", "item_name": f"ダミー商品{sku:02d}", "price": float(price), "quantity": qty}]
                         if ord_ >= 2 else [])
                out.append({
                    "event_date": date.strftime("%Y%m%d"), "event_timestamp": ts + ord_, "event_name": name,
                    "event_params": [
                        {"key": "ga_session_id", "value": {"string_value": None, "int_value": gsid, "float_value": None, "double_value": None}},
                        {"key": "page_location", "value": {"string_value": page, "int_value": None, "float_value": None, "double_value": None}},
                        {"key": "currency", "value": {"string_value": "JPY", "int_value": None, "float_value": None, "double_value": None}}],
                    "user_pseudo_id": f"dummy_{uid:05d}", "user_id": None,
                    "device": {"category": "mobile" if uid % 10 < 6 else "desktop"},
                    "geo": {"country": "Japan"},
                    "traffic_source": {"source": src, "medium": med, "name": camp},
                    "collected_traffic_source": {"manual_source": src, "manual_medium": med, "manual_campaign_name": camp, "gclid": None},
                    "ecommerce": eco, "items": items,
                    "session_traffic_source_last_click": {
                        "manual_campaign": manual,
                        "cross_channel_campaign": {"campaign_id": None, "campaign_name": camp, "source": src, "medium": med,
                                                   "source_platform": "Manual", "default_channel_group": grp}}})
    # T1: 同じ transaction_id の purchase を5件だけ複製（transaction_id の小さい順）
    pur = sorted((r for r in out if r["event_name"] == "purchase" and r["ecommerce"]["transaction_id"]),
                 key=lambda r: r["ecommerce"]["transaction_id"])
    out += [dict(r) for r in pur[:5]]
    return out


if __name__ == "__main__":
    for r in rows():
        sys.stdout.write(json.dumps(r, ensure_ascii=False) + "\n")
