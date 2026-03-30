from flask import Flask
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from pymongo import MongoClient
import os
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

CORS(app)

app.config['SECRET_KEY'] = os.getenv('SECRET_KEY')

limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

mongo_uri = os.getenv('MONGO_URI')

if not mongo_uri:
    raise ValueError("MONGO_URI environment variable required")

try:
    client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
    client.admin.command('ping')
    db = client.get_database()
    print("Connected to MongoDB successfully")
except Exception as e:
    print("Error connecting to MongoDB:", e)
    raise

# Seed dining halls into the database
DINING_HALLS = {
    "19": {"name": "Yahentamitsi Dining Hall", "location": "South Campus"},
    "51": {"name": "251 North", "location": "North Campus"},
    "16": {"name": "South Campus Diner", "location": "South Campus"},
}

for hall_id, info in DINING_HALLS.items():
    db.dining_halls.update_one(
        {"hall_id": hall_id},
        {"$set": {"hall_id": hall_id, "name": info["name"], "location": info["location"]}},
        upsert=True
    )
print(f"Seeded {len(DINING_HALLS)} dining halls")
