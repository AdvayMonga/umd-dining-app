"""
embedding_handler.py — Lambda entry point for the SQS-triggered embedding worker.

Triggered by: SQS queue "umd-dining-embeddings"
Batch size:   10 (recommended), max concurrency: 1 (to respect OpenAI rate limits)

Each SQS message body: {"rec_num": "<rec_num>"}

Uses partial batch response so only failed messages are retried, not the whole batch.
"""

import json
import os
from pymongo import MongoClient
from embeddings import generate_and_store_embedding

_mongo_client = None


def _get_db():
    global _mongo_client
    if _mongo_client is None:
        _mongo_client = MongoClient(os.environ['MONGO_URI'])
    return _mongo_client.get_database()


def handler(event, context):
    db = _get_db()
    batch_item_failures = []

    for record in event.get('Records', []):
        message_id = record['messageId']
        try:
            body = json.loads(record['body'])
            rec_num = body.get('rec_num')
            if not rec_num:
                continue  # malformed message — skip without retry

            food = db.foods.find_one({'rec_num': rec_num}, {'_id': 0})
            if not food:
                print(f"Food {rec_num} not found in db — skipping")
                continue

            generate_and_store_embedding(db, rec_num, food)
            print(f"Embedded {rec_num} ({food.get('name', '')})")

        except Exception as e:
            print(f"Failed to embed message {message_id}: {e}")
            batch_item_failures.append({'itemIdentifier': message_id})

    if batch_item_failures:
        print(f"Partial failures: {len(batch_item_failures)} of {len(event.get('Records', []))} messages will retry")

    return {'batchItemFailures': batch_item_failures}
