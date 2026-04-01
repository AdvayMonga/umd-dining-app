"""AWS Lambda handler for scheduled UMD dining hall scraping."""

import os
import json
from pymongo import MongoClient
from scraper_core import scrape_all_dining_halls

# Initialize MongoDB outside handler for connection reuse across warm starts
mongo_uri = os.environ["MONGO_URI"]
client = MongoClient(mongo_uri, serverSelectionTimeoutMS=10000)
db = client.get_database()


def lambda_handler(event, context):
    try:
        print("Starting scrape")

        items, failures = scrape_all_dining_halls(db)

        if failures:
            print(f"Scrape partial: {len(items)} items, {len(failures)} failures")
            for f in failures:
                print(f"  FAILED: {f}")

        status = 200 if not failures else (207 if items else 500)
        print(f"Scrape complete: {len(items)} items, {len(failures)} failures, status {status}")
        return {
            "statusCode": status,
            "body": json.dumps({
                "success": len(failures) == 0,
                "items_scraped": len(items),
                "failures": failures,
            }),
        }
    except Exception as e:
        print(f"Scrape failed: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"success": False, "error": str(e)}),
        }
