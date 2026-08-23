"""AWS Lambda handler for scheduled UMD dining hall scraping."""

import os
import json
import requests
from pymongo import MongoClient
from scraper_core import scrape_all_dining_halls

# Initialize MongoDB outside handler for connection reuse across warm starts
mongo_uri = os.environ["MONGO_URI"]
client = MongoClient(mongo_uri, serverSelectionTimeoutMS=10000)
db = client.get_database()

API_BASE_URL = os.environ.get("API_BASE_URL", "https://api.umddining.com")
ADMIN_SECRET = os.environ.get("ADMIN_SECRET", "")


def _trigger_backfill_similar():
    """Fire-and-forget call to the API server to backfill similar foods."""
    try:
        resp = requests.post(
            f"{API_BASE_URL}/api/backfill-similar",
            headers={"x-admin-key": ADMIN_SECRET},
            timeout=10,
        )
        print(f"Triggered backfill-similar: {resp.status_code}")
    except Exception as e:
        print(f"Failed to trigger backfill-similar: {e}")


def lambda_handler(event, context):
    try:
        print("Starting scrape")

        items, failures, new_food_count = scrape_all_dining_halls(db)

        if failures:
            print(f"Scrape partial: {len(items)} items, {len(failures)} failures")
            for f in failures:
                print(f"  FAILED: {f}")

        if new_food_count > 0:
            print(f"{new_food_count} new foods added — triggering similar foods backfill")
            _trigger_backfill_similar()

        status = 200 if not failures else (207 if items else 500)
        print(f"Scrape complete: {len(items)} items, {len(failures)} failures, {new_food_count} new foods, status {status}")
        return {
            "statusCode": status,
            "body": json.dumps({
                "success": len(failures) == 0,
                "items_scraped": len(items),
                "new_foods": new_food_count,
                "failures": failures,
            }),
        }
    except Exception as e:
        print(f"Scrape failed: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"success": False, "error": str(e)}),
        }
