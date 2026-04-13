from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from motor.motor_asyncio import AsyncIOMotorClient
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import jwt as pyjwt
import os
from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.getenv('SECRET_KEY')
ADMIN_SECRET = os.getenv('ADMIN_SECRET')


def _rate_limit_key(request: Request) -> str:
    """Rate limit by user ID from JWT if present, otherwise by IP."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        try:
            payload = pyjwt.decode(auth[7:], SECRET_KEY, algorithms=["HS256"])
            user_id = payload.get("user_id")
            if user_id:
                return f"user:{user_id}"
        except Exception:
            pass
    return get_remote_address(request)


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

limiter = Limiter(key_func=_rate_limit_key, default_limits=["200 per day", "50 per hour"])


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

    # --- Indexes for efficient queries at scale ---

    # Intake tracking
    await db.intake.create_index([('user_id', 1), ('date', 1)])
    await db.intake.create_index([('user_id', 1), ('rec_num', 1)])

    # Engagement tracking
    await db.item_views.create_index([('user_id', 1), ('timestamp', -1)])
    await db.item_views.create_index([('user_id', 1), ('rec_num', 1)])
    await db.item_views.create_index([('rec_num', 1), ('timestamp', -1)])
    await db.search_queries.create_index([('user_id', 1), ('timestamp', -1)])

    # Foods — text search on name + ingredients, rec_num lookup
    await db.foods.create_index([('rec_num', 1)], unique=True)
    await db.foods.create_index([('name', 'text'), ('ingredients', 'text')])

    # Menus — fast lookup by rec_num and by date+hall
    await db.menus.create_index([('rec_num', 1)])
    await db.menus.create_index([('date', 1), ('dining_hall_id', 1)])

    # Favorites — fast per-user and trending aggregation
    await db.favorites.create_index([('user_id', 1), ('rec_num', 1)])
    await db.favorites.create_index([('rec_num', 1)])

    # Station favorites
    await db.station_favorites.create_index([('user_id', 1), ('station_name', 1)])

    # Preferences
    await db.preferences.create_index([('user_id', 1)], unique=True)

    # Users
    await db.users.create_index([('user_id', 1)], unique=True)
    await db.users.create_index([('apple_user_id', 1)], sparse=True)

    yield

    # Shutdown
    client.close()


app = FastAPI(lifespan=lifespan)

app.state.limiter = limiter


@app.get("/health")
async def health_check():
    return {"status": "ok"}

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
