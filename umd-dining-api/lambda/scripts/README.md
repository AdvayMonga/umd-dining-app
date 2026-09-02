# Lambda deploy

`deploy.sh` ships the code in `lambda/` to the existing functions:

| Function | Files | Trigger |
|---|---|---|
| `umd-dining-scraper` | `handler.py`, `scraper_core.py` | EventBridge Scheduler: 7:00 AM, 12:00 PM, 5:00 PM ET |
| `umd-dining-embedding-worker` | `embedding_handler.py`, `embeddings.py` | SQS queue `umd-dining-embeddings` (batch 10, concurrency 1) |

Both use layer `umd-dining-scraper-layer` (requests, pymongo, bs4 deps) and
run on Python 3.12 in account 296433594974 (us-east-1).

```bash
AWS_PROFILE=umd-prod ./scripts/deploy.sh          # both
AWS_PROFILE=umd-prod ./scripts/deploy.sh scraper  # one
```

The original provisioning scripts (IAM roles, layer build, schedule creation)
were never git-tracked and are gone; the resources they created all exist.
If a function/layer/schedule ever needs recreating from scratch, rebuild the
layer from `lambda/requirements.txt` and recreate the three cron schedules
(`America/New_York`: `0 7 * * ? *`, `0 12 * * ? *`, `0 17 * * ? *`).
Env vars on the functions: MONGO_URI, and for the scraper API_BASE_URL +
ADMIN_SECRET (set in the Lambda console, not in git).
