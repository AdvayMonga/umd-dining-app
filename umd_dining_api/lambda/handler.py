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
        print("Starting scrape for 7 days")

        items = scrape_all_dining_halls(db)

        print(f"Scrape complete: {len(items)} items")
        return {
            "statusCode": 200,
            "body": json.dumps({
                "success": True,
                "items_scraped": len(items),
            }),
        }
    except Exception as e:
        print(f"Scrape failed: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"success": False, "error": str(e)}),
        }
