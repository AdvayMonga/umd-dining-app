import asyncio
import hashlib
import re
import time
import threading
import uuid
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt as pyjwt
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Body
from pydantic import BaseModel

from main import db, limiter, SECRET_KEY, ADMIN_SECRET
from scraper import scrape_all_dining_halls, scrape_dining_hall, scrape_full_week, fetch_and_cache_nutrition
from ranker import rank_items

router = APIRouter()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ensure_string(value, field_name='field'):
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f'{field_name} must be a string')
    return value


# --- Trending cache (global, 5-min TTL) ---
_trending_cache: dict = {'data': set(), 'expires': 0}

async def _get_trending():
    now = time.time()
    if now < _trending_cache['expires']:
        return _trending_cache['data']
    pipeline = [
        {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        {'$sort': {'count': -1}},
        {'$limit': 50}
    ]
    result = set()
    async for doc in db.favorites.aggregate(pipeline):
        result.add(doc['_id'])
    _trending_cache.update({'data': result, 'expires': now + 300})
    return result


# ---------------------------------------------------------------------------
# Auth dependencies
# ---------------------------------------------------------------------------

async def get_current_user(authorization: str = Header(default='')) -> str:
    if not authorization.startswith('Bearer '):
        raise HTTPException(status_code=401, detail='unauthorized')
    token = authorization[7:]
    try:
        payload = pyjwt.decode(token, SECRET_KEY, algorithms=['HS256'])
        return payload['sub']
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail='token expired')
    except pyjwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail='invalid token')


async def get_optional_user(authorization: str = Header(default='')) -> Optional[str]:
    if not authorization.startswith('Bearer '):
        return None
    try:
        payload = pyjwt.decode(authorization[7:], SECRET_KEY, algorithms=['HS256'])
        return payload['sub']
    except pyjwt.InvalidTokenError:
        return None


async def require_admin(x_admin_key: str = Header(default='')):
    if ADMIN_SECRET and x_admin_key != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail='unauthorized')


def _make_token(user_id: str) -> str:
    return pyjwt.encode(
        {'sub': user_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
        SECRET_KEY,
        algorithm='HS256'
    )


# ---------------------------------------------------------------------------
# Pydantic models for request bodies
# ---------------------------------------------------------------------------

class AppleAuthBody(BaseModel):
    apple_user_id: str

class FavoriteBody(BaseModel):
    rec_num: str
    name: str = ''

class RemoveFavoriteBody(BaseModel):
    rec_num: str

class StationFavoriteBody(BaseModel):
    station_name: str

class PreferencesBody(BaseModel):
    vegetarian: bool = False
    vegan: bool = False
    allergens: list[str] = []
    cuisine_prefs: list[str] = []

class IntakeBody(BaseModel):
    rec_num: str
    name: str = ''
    date: str = ''
    meal_period: str = ''
    calories: float = 0
    protein_g: float = 0.0
    carbs_g: float = 0.0
    fat_g: float = 0.0

class RemoveIntakeBody(BaseModel):
    rec_num: str
    date: str = ''
    logged_at: str = ''

class ItemViewBody(BaseModel):
    rec_num: str
    food_name: str = ''
    source: str = ''

class SearchQueryBody(BaseModel):
    query: str
    result_count: int = 0


# ---------------------------------------------------------------------------
# Public endpoints
# ---------------------------------------------------------------------------

@router.get('/')
async def home():
    return {
        'message': 'UMD Dining API is running!',
        'version': '3.0',
        'endpoints': {
            'dining_halls': '/api/dining-halls',
            'available_dates': '/api/available-dates',
            'menu': '/api/menu?date=...&dining_hall_id=...',
            'nutrition': '/api/nutrition?rec_num=...',
            'search': '/api/search?q=...',
            'scrape': 'POST /api/scrape'
        }
    }


@router.get('/api/dining-halls')
async def get_dining_halls():
    try:
        halls = await db.dining_halls.find({}, {'_id': 0}).to_list(None)
        return {'success': True, 'count': len(halls), 'data': halls}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/api/available-dates')
async def get_available_dates():
    try:
        dates = await db.menus.distinct("date")
        return {'success': True, 'count': len(dates), 'data': sorted(dates)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/api/ranked-menu')
@limiter.limit("60/minute")
async def get_ranked_menu(
    request: Request,
    date: str = Query(default=None),
    dining_hall_ids: list[str] = Query(default=['19', '51', '16']),
    user_id: Optional[str] = Depends(get_optional_user),
):
    try:
        if not date:
            raise HTTPException(status_code=400, detail='date required')

        # --- Phase 1: Parallel async DB queries ---
        async def fetch_menus():
            return await db.menus.find(
                {'date': date, 'dining_hall_id': {'$in': dining_hall_ids}},
                {'_id': 0}
            ).to_list(None)

        async def fetch_user_favs():
            if not user_id:
                return set()
            docs = await db.favorites.find({'user_id': user_id}, {'rec_num': 1, '_id': 0}).to_list(None)
            return {d['rec_num'] for d in docs}

        async def fetch_user_stations():
            if not user_id:
                return set()
            docs = await db.station_favorites.find({'user_id': user_id}, {'station_name': 1, '_id': 0}).to_list(None)
            return {d['station_name'] for d in docs}

        async def fetch_user_prefs():
            if not user_id:
                return {}
            return await db.preferences.find_one({'user_id': user_id}, {'_id': 0}) or {}

        async def fetch_user_view_counts():
            """Get rec_nums this user has viewed, with counts."""
            if not user_id:
                return {}
            pipeline = [
                {'$match': {'user_id': user_id}},
                {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
            ]
            result = {}
            async for doc in db.item_views.aggregate(pipeline):
                result[doc['_id']] = doc['count']
            return result

        async def fetch_global_view_counts():
            """Get view counts across all users for popularity signal."""
            pipeline = [
                {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
                {'$sort': {'count': -1}},
                {'$limit': 100},
            ]
            result = {}
            async for doc in db.item_views.aggregate(pipeline):
                result[doc['_id']] = doc['count']
            return result

        async def fetch_recent_hall_interest():
            """Get dining halls the user has recently engaged with."""
            if not user_id:
                return {}
            pipeline = [
                {'$match': {'user_id': user_id}},
                {'$sort': {'timestamp': -1}},
                {'$limit': 50},
                {'$lookup': {
                    'from': 'menus',
                    'localField': 'rec_num',
                    'foreignField': 'rec_num',
                    'as': 'menu_entry',
                }},
                {'$unwind': {'path': '$menu_entry', 'preserveNullAndEmptyArrays': False}},
                {'$group': {'_id': '$menu_entry.dining_hall_id', 'count': {'$sum': 1}}},
            ]
            result = {}
            async for doc in db.item_views.aggregate(pipeline):
                if doc['_id']:
                    result[doc['_id']] = doc['count']
            return result

        (menu_entries, fav_rec_nums, fav_stations, user_prefs,
         popular_rec_nums, user_views, global_views, hall_interest) = await asyncio.gather(
            fetch_menus(),
            fetch_user_favs(),
            fetch_user_stations(),
            fetch_user_prefs(),
            _get_trending(),
            fetch_user_view_counts(),
            fetch_global_view_counts(),
            fetch_recent_hall_interest(),
        )

        # --- Phase 2: Fetch foods (exclude embeddings) ---
        rec_nums = [e['rec_num'] for e in menu_entries]
        food_docs = await db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0, 'embedding': 0}).to_list(None)
        foods = {f['rec_num']: f for f in food_docs}

        # --- Phase 3: Fetch embeddings only if user has favorites ---
        fav_embeddings = []
        if user_id and fav_rec_nums:
            fav_food_docs = await db.foods.find(
                {'rec_num': {'$in': list(fav_rec_nums)}, 'embedding': {'$exists': True}},
                {'embedding': 1, '_id': 0}
            ).to_list(None)
            fav_embeddings = [doc['embedding'] for doc in fav_food_docs if doc.get('embedding')]

            if fav_embeddings:
                menu_emb_docs = await db.foods.find(
                    {'rec_num': {'$in': rec_nums}, 'embedding': {'$exists': True}},
                    {'rec_num': 1, 'embedding': 1, '_id': 0}
                ).to_list(None)
                for doc in menu_emb_docs:
                    if doc.get('embedding') and doc['rec_num'] in foods:
                        foods[doc['rec_num']]['embedding'] = doc['embedding']

        # Cold-start fallback
        if user_id and len(fav_embeddings) < 3 and user_prefs.get('cuisine_prefs'):
            cuisine_docs = await db.cuisine_embeddings.find(
                {'cuisine': {'$in': user_prefs['cuisine_prefs']}},
                {'embedding': 1, '_id': 0}
            ).to_list(None)
            cuisine_embs = [doc['embedding'] for doc in cuisine_docs if doc.get('embedding')]
            if cuisine_embs:
                fav_embeddings = cuisine_embs

        result = rank_items(
            menu_entries=menu_entries,
            foods=foods,
            fav_rec_nums=fav_rec_nums,
            fav_stations=fav_stations,
            user_prefs=user_prefs,
            popular_rec_nums=popular_rec_nums,
            date_seed=date,
            fav_embeddings=fav_embeddings,
            user_views=user_views,
            global_views=global_views,
            hall_interest=hall_interest,
        )

        return {'success': True, 'count': len(result), 'data': result}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/api/menu')
async def get_menu(
    date: Optional[str] = Query(default=None),
    dining_hall_id: Optional[str] = Query(default=None),
):
    try:
        query: dict = {}
        if dining_hall_id:
            query['dining_hall_id'] = dining_hall_id
        if date:
            query['date'] = date

        menu_entries = await db.menus.find(query, {'_id': 0}).to_list(None)
        rec_nums = [entry['rec_num'] for entry in menu_entries]
        food_docs = await db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0}).to_list(None)
        foods = {f['rec_num']: f for f in food_docs}

        items = []
        for entry in menu_entries:
            food = foods.get(entry['rec_num'], {})
            items.append({
                'name': food.get('name', ''),
                'rec_num': entry['rec_num'],
                'dining_hall_id': entry['dining_hall_id'],
                'date': entry['date'],
                'meal_period': entry.get('meal_period', 'Unknown'),
                'station': entry.get('station', 'Unknown'),
                'dietary_icons': entry.get('dietary_icons', []),
                'nutrition_fetched': food.get('nutrition_fetched', False),
                'nutrition': food.get('nutrition', {}),
                'allergens': food.get('allergens', ''),
                'ingredients': food.get('ingredients', ''),
            })

        return {'success': True, 'count': len(items), 'filters': query, 'data': items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/api/nutrition')
@limiter.limit("60/minute")
async def get_nutrition(request: Request, rec_num: str = Query(default=None)):
    try:
        if not rec_num:
            raise HTTPException(status_code=400, detail='rec_num parameter required')

        # fetch_and_cache_nutrition is sync (hits UMD's site) — run in thread
        loop = asyncio.get_event_loop()
        food = await loop.run_in_executor(None, fetch_and_cache_nutrition, rec_num)
        if not food:
            raise HTTPException(status_code=404, detail='Food not found')

        return {
            'success': True,
            'data': {
                'rec_num': food['rec_num'],
                'name': food.get('name', ''),
                'nutrition': food.get('nutrition', {}),
                'allergens': food.get('allergens', ''),
                'ingredients': food.get('ingredients', ''),
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/api/search')
@limiter.limit("30/minute")
async def search_menu(request: Request, q: str = Query(default='')):
    try:
        if not q:
            raise HTTPException(status_code=400, detail='Search query required')
        if len(q) > 100:
            raise HTTPException(status_code=400, detail='Search query too long')

        safe_query = re.escape(q)
        foods = await db.foods.find(
            {'name': {'$regex': safe_query, '$options': 'i'}},
            {'_id': 0, 'embedding': 0}
        ).limit(50).to_list(None)

        # Look up most recent station + dining hall for each food from menus
        rec_nums = [f['rec_num'] for f in foods]
        if rec_nums:
            menu_entries = await db.menus.find(
                {'rec_num': {'$in': rec_nums}},
                {'_id': 0, 'rec_num': 1, 'station': 1, 'dining_hall_id': 1}
            ).sort('date', -1).to_list(None)
            # Keep only the most recent entry per rec_num
            location_map = {}
            for entry in menu_entries:
                rn = entry['rec_num']
                if rn not in location_map:
                    hall_id = entry.get('dining_hall_id', '')
                    hall_doc = await db.dining_halls.find_one({'hall_id': hall_id}, {'_id': 0, 'name': 1})
                    location_map[rn] = {
                        'station': entry.get('station', ''),
                        'dining_hall_id': hall_id,
                        'dining_hall_name': hall_doc['name'] if hall_doc else '',
                    }
            for food in foods:
                loc = location_map.get(food['rec_num'], {})
                food['station'] = loc.get('station', '')
                food['dining_hall_id'] = loc.get('dining_hall_id', '')
                food['dining_hall_name'] = loc.get('dining_hall_name', '')

        return {'success': True, 'query': q, 'count': len(foods), 'data': foods}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Engagement tracking
# ---------------------------------------------------------------------------

@router.post('/api/track/item-view')
@limiter.limit("120/minute")
async def track_item_view(
    request: Request,
    body: ItemViewBody,
    user_id: Optional[str] = Depends(get_optional_user),
):
    allowed_sources = {'home', 'station', 'search', 'profile_favorites', 'tracker'}
    source = body.source if body.source in allowed_sources else 'unknown'
    await db.item_views.insert_one({
        'user_id': user_id,
        'rec_num': body.rec_num,
        'food_name': body.food_name,
        'source': source,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })
    return {'success': True}


@router.post('/api/track/search-query')
@limiter.limit("60/minute")
async def track_search_query(
    request: Request,
    body: SearchQueryBody,
    user_id: Optional[str] = Depends(get_optional_user),
):
    if len(body.query) > 200:
        return {'success': True}
    await db.search_queries.insert_one({
        'user_id': user_id,
        'query': body.query,
        'result_count': body.result_count,
        'timestamp': datetime.now(timezone.utc).isoformat(),
    })
    return {'success': True}


# ---------------------------------------------------------------------------
# Admin endpoints
# ---------------------------------------------------------------------------

@router.post('/api/scrape')
async def scrape(
    date: Optional[str] = Query(default=None),
    dining_hall_id: Optional[str] = Query(default=None),
    _: None = Depends(require_admin),
):
    scrape_date = date or datetime.now().strftime('%-m/%-d/%Y')
    if dining_hall_id:
        threading.Thread(target=scrape_dining_hall, args=(dining_hall_id, scrape_date), daemon=False).start()
    else:
        threading.Thread(target=scrape_all_dining_halls, args=(scrape_date,), daemon=False).start()
    return {'success': True, 'date': scrape_date, 'status': 'scrape started'}


@router.post('/api/scrape-week')
async def scrape_week(_: None = Depends(require_admin)):
    threading.Thread(target=scrape_full_week, daemon=False).start()
    return {'success': True, 'status': 'scrape started'}


@router.post('/api/embed-missing')
async def embed_missing(_: None = Depends(require_admin)):
    def _run():
        from embeddings import generate_and_store_embedding
        from pymongo import MongoClient
        import time as _time
        sync_client = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
        sync_db = sync_client.get_default_database()
        for food in sync_db.foods.find({'embedding': {'$exists': False}}, {'_id': 0}):
            try:
                generate_and_store_embedding(sync_db, food['rec_num'], food)
                _time.sleep(0.1)
            except Exception as e:
                print(f"Embedding failed for {food['rec_num']}: {e}")
        sync_client.close()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'embedding started in background'}


@router.post('/api/cuisine-embeddings/generate')
async def generate_cuisine_embeddings(_: None = Depends(require_admin)):
    from embeddings import generate_embedding, compute_centroid
    from pymongo import MongoClient
    import time as _time

    CUISINES = {
        'comfort': ['Cheeseburger', 'Mac and Cheese', 'Grilled Cheese Sandwich', 'French Fries', 'Chicken Tenders'],
        'asian': ['Teriyaki Chicken', 'Vegetable Stir Fry', 'Fried Rice', 'Lo Mein Noodles', 'Orange Chicken'],
        'mexican': ['Chicken Burrito', 'Beef Tacos', 'Cheese Quesadilla', 'Spanish Rice and Beans', 'Nachos'],
        'italian': ['Spaghetti Marinara', 'Cheese Pizza', 'Caesar Salad', 'Chicken Parmesan', 'Penne Alfredo'],
        'indian': ['Chicken Tikka Masala', 'Butter Chicken Curry', 'Vegetable Biryani', 'Naan Bread', 'Chana Masala'],
        'southern': ['Fried Chicken', 'Cornbread', 'Collard Greens', 'Mashed Potatoes and Gravy', 'BBQ Pulled Pork'],
        'breakfast': ['Pancakes with Syrup', 'Scrambled Eggs and Bacon', 'French Toast', 'Breakfast Burrito', 'Waffles'],
    }

    sync_client = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
    sync_db = sync_client.get_default_database()

    results = {}
    for cuisine, food_names in CUISINES.items():
        embeddings = []
        for food_name in food_names:
            try:
                emb = generate_embedding(food_name)
                embeddings.append(emb)
                _time.sleep(0.1)
            except Exception as e:
                print(f"Failed to embed {food_name}: {e}")

        if embeddings:
            centroid = compute_centroid(embeddings)
            sync_db.cuisine_embeddings.update_one(
                {'cuisine': cuisine},
                {'$set': {'cuisine': cuisine, 'embedding': centroid}},
                upsert=True
            )
            results[cuisine] = len(embeddings)

    sync_client.close()
    return {'success': True, 'generated': results}


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

@router.post('/api/auth/guest')
@limiter.limit("10/minute")
async def auth_guest(request: Request):
    try:
        guest_id = f"guest_{uuid.uuid4().hex}"
        await db.users.insert_one({
            'user_id': guest_id,
            'is_guest': True,
            'created_at': datetime.now().isoformat()
        })
        return {'success': True, 'user_id': guest_id, 'token': _make_token(guest_id)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/auth/apple')
@limiter.limit("10/minute")
async def auth_apple(request: Request, body: AppleAuthBody = Body(...)):
    try:
        if not body.apple_user_id:
            raise HTTPException(status_code=400, detail='apple_user_id required')

        await db.users.update_one(
            {'apple_user_id': body.apple_user_id},
            {'$setOnInsert': {'apple_user_id': body.apple_user_id, 'created_at': datetime.now().isoformat()}},
            upsert=True
        )
        return {'success': True, 'user_id': body.apple_user_id, 'token': _make_token(body.apple_user_id)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/auth/upgrade')
@limiter.limit("10/minute")
async def upgrade_guest(
    request: Request,
    body: AppleAuthBody = Body(...),
    user_id: str = Depends(get_current_user),
):
    try:
        if not body.apple_user_id:
            raise HTTPException(status_code=400, detail='apple_user_id required')
        if not user_id.startswith('guest_'):
            raise HTTPException(status_code=400, detail='not a guest account')

        await db.users.update_one(
            {'apple_user_id': body.apple_user_id},
            {'$setOnInsert': {'apple_user_id': body.apple_user_id, 'created_at': datetime.now().isoformat()}},
            upsert=True
        )

        # Migrate all user data
        for coll in [db.favorites, db.station_favorites, db.preferences, db.intake]:
            await coll.update_many({'user_id': user_id}, {'$set': {'user_id': body.apple_user_id}})

        await db.users.delete_one({'user_id': user_id})

        return {'success': True, 'user_id': body.apple_user_id, 'token': _make_token(body.apple_user_id)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/auth/refresh')
@limiter.limit("10/minute")
async def refresh_token(request: Request, user_id: str = Depends(get_current_user)):
    try:
        return {'success': True, 'token': _make_token(user_id)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


async def _archive_user_data(user_id: str):
    """Anonymize all behavioral data for ML training, then delete the identity."""
    anon_id = 'anon_' + hashlib.sha256(user_id.encode()).hexdigest()[:16]

    for coll in [db.favorites, db.station_favorites, db.preferences, db.intake, db.item_views, db.search_queries]:
        await coll.update_many({'user_id': user_id}, {'$set': {'user_id': anon_id}})

    await db.users.delete_one({'user_id': user_id})


@router.delete('/api/auth/account')
@limiter.limit("5/minute")
async def delete_account(request: Request, user_id: str = Depends(get_current_user)):
    try:
        await _archive_user_data(user_id)
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Favorites
# ---------------------------------------------------------------------------

@router.get('/api/favorites')
async def get_favorites(user_id: str = Depends(get_current_user)):
    try:
        favs = await db.favorites.find({'user_id': user_id}, {'_id': 0}).to_list(None)
        return {'success': True, 'data': favs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/favorites')
async def add_favorite(body: FavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        await db.favorites.update_one(
            {'user_id': user_id, 'rec_num': body.rec_num},
            {'$set': {'user_id': user_id, 'rec_num': body.rec_num, 'name': body.name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete('/api/favorites')
async def remove_favorite(body: RemoveFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        await db.favorites.delete_one({'user_id': user_id, 'rec_num': body.rec_num})
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Station Favorites
# ---------------------------------------------------------------------------

@router.get('/api/station-favorites')
async def get_station_favorites(user_id: str = Depends(get_current_user)):
    try:
        favs = await db.station_favorites.find({'user_id': user_id}, {'_id': 0}).to_list(None)
        return {'success': True, 'data': favs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/station-favorites')
async def add_station_favorite(body: StationFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        await db.station_favorites.update_one(
            {'user_id': user_id, 'station_name': body.station_name},
            {'$set': {'user_id': user_id, 'station_name': body.station_name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete('/api/station-favorites')
async def remove_station_favorite(body: StationFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        await db.station_favorites.delete_one({'user_id': user_id, 'station_name': body.station_name})
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Preferences
# ---------------------------------------------------------------------------

@router.get('/api/preferences')
async def get_preferences(user_id: str = Depends(get_current_user)):
    try:
        prefs = await db.preferences.find_one({'user_id': user_id}, {'_id': 0})
        if not prefs:
            prefs = {'user_id': user_id, 'vegetarian': False, 'vegan': False, 'allergens': [], 'cuisine_prefs': []}
        return {'success': True, 'data': prefs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put('/api/preferences')
async def update_preferences(body: PreferencesBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        await db.preferences.update_one(
            {'user_id': user_id},
            {'$set': {
                'user_id': user_id,
                'vegetarian': body.vegetarian,
                'vegan': body.vegan,
                'allergens': body.allergens,
                'cuisine_prefs': body.cuisine_prefs,
            }},
            upsert=True
        )
        return {'success': True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ---------------------------------------------------------------------------
# Intake Tracking
# ---------------------------------------------------------------------------

@router.get('/api/intake')
async def get_intake(date: Optional[str] = Query(default=None), user_id: str = Depends(get_current_user)):
    try:
        query: dict = {'user_id': user_id}
        if date:
            query['date'] = date
        items = await db.intake.find(query, {'_id': 0}).to_list(None)
        return {'success': True, 'data': items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post('/api/intake')
async def log_intake(body: IntakeBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        if not body.rec_num:
            raise HTTPException(status_code=400, detail='rec_num required')

        await db.intake.insert_one({
            'user_id': user_id,
            'rec_num': body.rec_num,
            'name': body.name,
            'date': body.date,
            'meal_period': body.meal_period,
            'calories': int(body.calories),
            'protein_g': float(body.protein_g),
            'carbs_g': float(body.carbs_g),
            'fat_g': float(body.fat_g),
            'logged_at': datetime.now().isoformat(),
        })
        return {'success': True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete('/api/intake')
async def remove_intake(body: RemoveIntakeBody = Body(...), user_id: str = Depends(get_current_user)):
    try:
        if not body.rec_num:
            raise HTTPException(status_code=400, detail='rec_num required')

        query: dict = {'user_id': user_id, 'rec_num': body.rec_num}
        if body.date:
            query['date'] = body.date
        if body.logged_at:
            query['logged_at'] = body.logged_at

        await db.intake.delete_one(query)
        return {'success': True}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
