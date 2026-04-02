from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from motor.motor_asyncio import AsyncIOMotorClient
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import os
from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.getenv('SECRET_KEY')
ADMIN_SECRET = os.getenv('ADMIN_SECRET')

mongo_uri = os.getenv('MONGO_URI')
if not mongo_uri:
    raise ValueError("MONGO_URI environment variable required")

# Motor async client — initialized at module level, connected during lifespan
client = AsyncIOMotorClient(mongo_uri, serverSelectionTimeoutMS=5000)
db = client.get_default_database()

DINING_HALLS = {
    "19": {"name": "Yahentamitsi Dining Hall", "location": "South Campus"},
    "51": {"name": "251 North", "location": "North Campus"},
    "16": {"name": "South Campus Diner", "location": "South Campus"},
}

limiter = Limiter(key_func=get_remote_address, default_limits=["200 per day", "50 per hour"])


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: verify connection, seed data, create indexes
    await client.admin.command('ping')
    print("Connected to MongoDB successfully")

    for hall_id, info in DINING_HALLS.items():
        await db.dining_halls.update_one(
            {"hall_id": hall_id},
            {"$set": {"hall_id": hall_id, "name": info["name"], "location": info["location"]}},
            upsert=True
        )
    print(f"Seeded {len(DINING_HALLS)} dining halls")

    await db.intake.create_index([('user_id', 1), ('date', 1)])

    # Engagement tracking indexes
    await db.item_views.create_index([('user_id', 1), ('timestamp', -1)])
    await db.item_views.create_index([('rec_num', 1), ('timestamp', -1)])
    await db.search_queries.create_index([('user_id', 1), ('timestamp', -1)])

    yield

    # Shutdown
    client.close()


app = FastAPI(lifespan=lifespan)

app.state.limiter = limiter

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(status_code=429, content={"success": False, "error": "Rate limit exceeded"})


# Import routes to register them
from routes import router  # noqa: E402
app.include_router(router)
