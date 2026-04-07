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
from search_ranker import rank_search_results
from embeddings import generate_embedding_async

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

# --- Guest response cache (5-min TTL) ---
_guest_menu_cache: dict = {}  # {cache_key: {'data': response_dict, 'expires': float}}

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


# --- Global view counts cache (5-min TTL) ---
_global_views_cache: dict = {'data': {}, 'expires': 0}

async def _get_global_views():
    now = time.time()
    if now < _global_views_cache['expires']:
        return _global_views_cache['data']
    pipeline = [
        {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        {'$sort': {'count': -1}},
        {'$limit': 100},
    ]
    result = {}
    async for doc in db.item_views.aggregate(pipeline):
        result[doc['_id']] = doc['count']
    _global_views_cache.update({'data': result, 'expires': now + 300})
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
    from fastapi.responses import HTMLResponse
    return HTMLResponse("""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UMD Dining</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,system-ui,sans-serif;background:#000;color:#fff;min-height:100vh;display:flex;align-items:center;justify-content:center}
.container{text-align:center;max-width:480px;padding:60px 24px}
h1{font-size:36px;font-weight:700;color:#E21833;margin-bottom:6px;letter-spacing:-0.5px}
.subtitle{font-size:14px;color:#E21833;opacity:0.7;text-transform:uppercase;letter-spacing:2px;margin-bottom:24px}
.tagline{font-size:17px;color:#8e8e93;margin-bottom:40px;line-height:1.6}
.features{text-align:left;margin:0 auto 40px;max-width:340px}
.feature{display:flex;align-items:center;gap:14px;padding:14px 16px;margin-bottom:8px;background:#1c1c1e;border-radius:12px;border:1px solid #2c2c2e}
.feature-icon{font-size:20px;width:28px;text-align:center;flex-shrink:0}
.feature-text{font-size:15px;color:#e5e5e7}
.btn{display:inline-block;font-size:15px;font-weight:600;padding:14px 32px;border-radius:12px;text-decoration:none;transition:opacity 0.2s}
.btn:hover{opacity:0.85}
.btn-primary{background:#E21833;color:#fff;margin-bottom:12px}
.btn-secondary{background:transparent;color:#8e8e93;border:1px solid #3a3a3c;margin-bottom:12px}
.links{margin-top:20px;font-size:13px;color:#48484a}
.links a{color:#8e8e93;text-decoration:none}
.links a:hover{color:#E21833}
.divider{width:40px;height:2px;background:#E21833;margin:0 auto 24px;border-radius:1px}
</style>
</head><body>
<div class="container">
<h1>UMD Dining</h1>
<p class="subtitle">University of Maryland</p>
<div class="divider"></div>
<p class="tagline">Personalized dining hall recommendations powered by AI. Find what you want to eat, track your nutrition, and never miss your favorites.</p>
<div class="features">
<div class="feature"><span class="feature-icon">🎯</span><span class="feature-text">AI-powered food recommendations</span></div>
<div class="feature"><span class="feature-icon">🥗</span><span class="feature-text">Dietary filters &amp; allergen alerts</span></div>
<div class="feature"><span class="feature-icon">📊</span><span class="feature-text">Nutrition tracking &amp; daily goals</span></div>
<div class="feature"><span class="feature-icon">❤️</span><span class="feature-text">Save favorites across all dining halls</span></div>
<div class="feature"><span class="feature-icon">🔍</span><span class="feature-text">Search any food with smart results</span></div>
</div>
<a href="https://forms.gle/53RrYDkmZjmf72Py9" target="_blank" class="btn btn-secondary">Send Feedback</a>
<div class="links"><a href="/privacy">Privacy Policy</a></div>
</div>
</body></html>""")


@router.get('/privacy')
async def privacy_policy():
    from fastapi.responses import HTMLResponse
    return HTMLResponse("""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>UMD Dining - Privacy Policy</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;max-width:700px;margin:40px auto;padding:0 20px;color:#333;line-height:1.6}h1{color:#E21833}h2{margin-top:30px}ul{padding-left:20px}</style>
</head><body>
<h1>UMD Dining — Privacy Policy</h1>
<p><strong>Last updated:</strong> April 3, 2026</p>

<h2>What We Collect</h2>
<ul>
<li><strong>Apple Sign In ID</strong> — Used solely to authenticate your account. We do not access your name or email.</li>
<li><strong>Dietary preferences &amp; allergens</strong> — Stored to personalize your feed and filter foods.</li>
<li><strong>Favorites &amp; intake logs</strong> — Stored to track your favorite foods and nutrition intake.</li>
<li><strong>Usage data</strong> — Food views and search queries to improve recommendations. This data is anonymous and not tied to your identity.</li>
</ul>

<h2>How We Use Your Data</h2>
<ul>
<li>Personalize your dining hall food recommendations</li>
<li>Remember your dietary preferences and allergens</li>
<li>Track your nutrition intake</li>
<li>Improve the app's recommendation algorithm</li>
</ul>

<h2>Data Security</h2>
<p>Your data is encrypted in transit and at rest. We do not sell, share, or provide your personal data to third parties.</p>

<h2>Account Deletion</h2>
<p>You can delete your account at any time from the Profile tab. This permanently removes your account and personal data. Anonymous usage data may be retained to improve the service.</p>

<h2>Third-Party Services</h2>
<ul>
<li><strong>Apple Sign In</strong> — For authentication only</li>
<li><strong>University of Maryland Dining Services</strong> — Source of menu and nutrition data</li>
</ul>

<h2>Changes to This Policy</h2>
<p>We may update this policy from time to time. Continued use of the app constitutes acceptance of any changes.</p>

<h2>Contact</h2>
<p>Questions or concerns? <a href="https://forms.gle/53RrYDkmZjmf72Py9" style="color:#E21833">Send us feedback</a></p>
</body></html>""")


@router.get('/api/dining-halls')
@limiter.limit("30/minute")
async def get_dining_halls(request: Request):
    halls = await db.dining_halls.find({}, {'_id': 0}).to_list(None)
    return {'success': True, 'count': len(halls), 'data': halls}


@router.get('/api/available-dates')
@limiter.limit("30/minute")
async def get_available_dates(request: Request):
    dates = await db.menus.distinct("date")
    return {'success': True, 'count': len(dates), 'data': sorted(dates)}


@router.get('/api/ranked-menu')
@limiter.limit("60/minute")
async def get_ranked_menu(
    request: Request,
    date: str = Query(default=None),
    dining_hall_ids: list[str] = Query(default=['19', '51', '16']),
    user_id: Optional[str] = Depends(get_optional_user),
    vegetarian: bool = Query(default=False),
    vegan: bool = Query(default=False),
    high_protein: bool = Query(default=False),
    allergens: list[str] = Query(default=[]),
):
    if not date:
        raise HTTPException(status_code=400, detail='date required')

    # --- Guest response cache ---
    is_guest = user_id is None
    if is_guest:
        cache_key = (date, tuple(sorted(dining_hall_ids)), vegetarian, vegan, high_protein, tuple(sorted(allergens)))
        now = time.time()
        cached = _guest_menu_cache.get(cache_key)
        if cached and now < cached['expires']:
            return cached['data']

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
        """Get rec_nums this user has viewed in the last 14 days, with counts."""
        if not user_id:
            return {}
        cutoff = (datetime.now(timezone.utc) - timedelta(days=14)).isoformat()
        pipeline = [
            {'$match': {'user_id': user_id, 'timestamp': {'$gte': cutoff}}},
            {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        ]
        result = {}
        async for doc in db.item_views.aggregate(pipeline):
            result[doc['_id']] = doc['count']
        return result

    async def fetch_global_view_counts():
        """Get view counts across all users (cached 5 min like trending)."""
        return await _get_global_views()

    async def fetch_recent_hall_interest():
        """Get dining halls the user has recently engaged with (last 14 days)."""
        if not user_id:
            return {}
        cutoff = (datetime.now(timezone.utc) - timedelta(days=14)).isoformat()
        docs = await db.item_views.find(
            {'user_id': user_id, 'timestamp': {'$gte': cutoff}},
            {'_id': 0, 'rec_num': 1}
        ).sort('timestamp', -1).limit(50).to_list(None)
        if not docs:
            return {}
        # Count which dining halls these rec_nums belong to using today's menu
        view_rec_nums = [d['rec_num'] for d in docs]
        menu_docs = await db.menus.find(
            {'rec_num': {'$in': view_rec_nums}, 'date': date},
            {'_id': 0, 'rec_num': 1, 'dining_hall_id': 1}
        ).to_list(None)
        hall_map = {}
        for m in menu_docs:
            if m['rec_num'] not in hall_map:
                hall_map[m['rec_num']] = m['dining_hall_id']
        result = {}
        for d in docs:
            hall_id = hall_map.get(d['rec_num'])
            if hall_id:
                result[hall_id] = result.get(hall_id, 0) + 1
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

    # --- Phase 2.5: Apply dietary filters before ranking ---
    has_filters = vegetarian or vegan or high_protein or allergens
    if has_filters:
        filtered_entries = []
        for entry in menu_entries:
            icons = entry.get('dietary_icons', [])
            if vegan and 'vegan' not in icons:
                continue
            if vegetarian and 'vegetarian' not in icons:
                continue
            if allergens and any(a in icons for a in allergens):
                continue
            if high_protein:
                food = foods.get(entry['rec_num'], {})
                nutrition = food.get('nutrition') or {}
                protein_str = nutrition.get('Protein', nutrition.get('Protein.', ''))
                digits = ''.join(c for c in str(protein_str) if c.isdigit() or c == '.')
                try:
                    grams = float(digits) if digits else 0
                except ValueError:
                    grams = 0
                if grams < 15:
                    continue
            filtered_entries.append(entry)
        menu_entries = filtered_entries

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

    # Blend cuisine centroids: full strength at 0 favs, linearly decreasing to 0.5 at 20+ favs
    if user_id and user_prefs.get('cuisine_prefs'):
        cuisine_docs = await db.cuisine_embeddings.find(
            {'cuisine': {'$in': user_prefs['cuisine_prefs']}},
            {'embedding': 1, '_id': 0}
        ).to_list(None)
        cuisine_embs = [doc['embedding'] for doc in cuisine_docs if doc.get('embedding')]
        if cuisine_embs:
            import numpy as np
            num_favs = len(fav_embeddings)
            weight = 1.0 - 0.5 * min(num_favs, 20) / 20  # 1.0 → 0.5 over 0–20 favs
            weighted = [(np.asarray(e, dtype=np.float32) * weight).tolist() for e in cuisine_embs]
            fav_embeddings = fav_embeddings + weighted

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

    response = {'success': True, 'count': len(result), 'data': result}

    # Cache guest responses for 5 minutes
    if is_guest:
        _guest_menu_cache[cache_key] = {'data': response, 'expires': time.time() + 300}
        if len(_guest_menu_cache) > 50:
            stale = [k for k, v in _guest_menu_cache.items() if time.time() >= v['expires']]
            for k in stale:
                del _guest_menu_cache[k]

    return response


@router.get('/api/menu')
@limiter.limit("30/minute")
async def get_menu(
    request: Request,
    date: Optional[str] = Query(default=None),
    dining_hall_id: Optional[str] = Query(default=None),
):
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


@router.get('/api/nutrition')
@limiter.limit("60/minute")
async def get_nutrition(request: Request, rec_num: str = Query(default=None)):
    if not rec_num:
        raise HTTPException(status_code=400, detail='rec_num parameter required')

    # Fast path: read from async Motor client (most foods already have nutrition)
    food = await db.foods.find_one({'rec_num': rec_num}, {'_id': 0, 'embedding': 0})
    if not food:
        raise HTTPException(status_code=404, detail='Food not found')

    # If nutrition not fetched yet, kick off background scrape but return what we have now
    if not food.get('nutrition_fetched'):
        import threading
        threading.Thread(target=fetch_and_cache_nutrition, args=(rec_num,), daemon=True).start()

    # Find next available date (today or future)
    from datetime import datetime as dt
    today = dt.now().date()
    menu_dates = await db.menus.distinct('date', {'rec_num': rec_num})
    next_available = None
    earliest_future = None
    for d in menu_dates:
        try:
            parsed = dt.strptime(d, '%m/%d/%Y').date()
            if parsed >= today and (earliest_future is None or parsed < earliest_future):
                earliest_future = parsed
                next_available = d
        except ValueError:
            pass

    return {
        'success': True,
        'data': {
            'rec_num': food['rec_num'],
            'name': food.get('name', ''),
            'nutrition': food.get('nutrition', {}),
            'allergens': food.get('allergens', ''),
            'ingredients': food.get('ingredients', ''),
            'next_available': next_available,
        }
    }


@router.get('/api/nutrition/similar')
@limiter.limit("30/minute")
async def get_similar_foods(
    request: Request,
    rec_num: str = Query(default=None),
    limit: int = Query(default=5, le=5),
    date: Optional[str] = Query(default=None),
):
    if not rec_num:
        raise HTTPException(status_code=400, detail='rec_num required')

    SIMILARITY_THRESHOLD = 0.55

    # Lookup precomputed similar foods — just two DB reads
    food = await db.foods.find_one({'rec_num': rec_num}, {'_id': 0, 'similar': 1})
    if not food or not food.get('similar'):
        return {'success': True, 'data': []}

    # Show 3-5: all that pass threshold (up to 5), but always at least 3
    stored = food['similar']  # [{rec_num, score}, ...]
    above_threshold = [s for s in stored if s.get('score', 0) >= SIMILARITY_THRESHOLD]
    if len(above_threshold) >= 3:
        selected = above_threshold[:5]
    else:
        selected = stored[:3]

    similar_rec_nums = [s['rec_num'] for s in selected]

    # Fetch food data for similar items
    food_docs = await db.foods.find(
        {'rec_num': {'$in': similar_rec_nums}},
        {'_id': 0, 'embedding': 0}
    ).to_list(None)
    food_map = {f['rec_num']: f for f in food_docs}

    # Look up station/dining hall from most recent menu entries
    menu_entries = await db.menus.find(
        {'rec_num': {'$in': similar_rec_nums}},
        {'_id': 0, 'rec_num': 1, 'station': 1, 'dining_hall_id': 1, 'dietary_icons': 1,
         'date': 1, 'meal_period': 1}
    ).sort('date', -1).to_list(None)

    hall_names = {}
    location_map = {}
    for entry in menu_entries:
        rn = entry['rec_num']
        if rn not in location_map:
            hall_id = entry.get('dining_hall_id', '')
            if hall_id and hall_id not in hall_names:
                hall_doc = await db.dining_halls.find_one({'hall_id': hall_id}, {'_id': 0, 'name': 1})
                hall_names[hall_id] = hall_doc['name'] if hall_doc else ''
            location_map[rn] = {
                'station': entry.get('station', ''),
                'dining_hall_id': hall_id,
                'dining_hall_name': hall_names.get(hall_id, ''),
                'dietary_icons': entry.get('dietary_icons', []),
                'date': entry.get('date', ''),
                'meal_period': entry.get('meal_period', ''),
            }

    data = []
    for rn in similar_rec_nums:
        f = food_map.get(rn, {})
        loc = location_map.get(rn, {})
        data.append({
            'name': f.get('name', ''),
            'rec_num': rn,
            'station': loc.get('station', ''),
            'dining_hall_id': loc.get('dining_hall_id', ''),
            'date': loc.get('date', ''),
            'meal_period': loc.get('meal_period', ''),
            'dietary_icons': loc.get('dietary_icons', []),
            'nutrition': f.get('nutrition', {}),
            'nutrition_fetched': f.get('nutrition_fetched', False),
            'allergens': f.get('allergens', ''),
            'ingredients': f.get('ingredients', ''),
            'tag': None,
            'tags': [],
        })

    return {'success': True, 'data': data}


# --- Query embedding cache (1-hr TTL, max 200 entries) ---
_query_embed_cache: dict = {}  # {query_lower: {'embedding': [...], 'expires': float}}

# --- Food embedding matrix cache (5-min TTL) ---

async def _get_query_embedding(query: str):
    """Get or generate query embedding with caching. Returns None on timeout/error."""
    key = query.lower().strip()
    now = time.time()
    cached = _query_embed_cache.get(key)
    if cached and now < cached['expires']:
        return cached['embedding']
    try:
        embedding = await asyncio.wait_for(generate_embedding_async(key), timeout=3.0)
        _query_embed_cache[key] = {'embedding': embedding, 'expires': now + 3600}
        # Evict expired entries if cache is large
        if len(_query_embed_cache) > 200:
            stale = [k for k, v in _query_embed_cache.items() if now >= v['expires']]
            for k in stale:
                del _query_embed_cache[k]
        return embedding
    except Exception:
        return None


async def _get_candidate_embeddings(rec_nums: list):
    """Fetch embeddings only for specific candidate rec_nums. Lightweight — no full scan."""
    if not rec_nums:
        return [], None
    docs = await db.foods.find(
        {'rec_num': {'$in': rec_nums}, 'embedding': {'$exists': True, '$ne': None}},
        {'_id': 0, 'rec_num': 1, 'embedding': 1}
    ).to_list(None)
    if not docs:
        return [], None
    import numpy as np
    rns = [d['rec_num'] for d in docs]
    matrix = np.array([d['embedding'] for d in docs], dtype=np.float32)
    return rns, matrix


@router.get('/api/search')
@limiter.limit("30/minute")
async def search_menu(
    request: Request,
    q: str = Query(default=''),
    semantic: bool = Query(default=False),
    user_id: Optional[str] = Depends(get_optional_user),
):
    if not q:
        raise HTTPException(status_code=400, detail='Search query required')
    if len(q) > 100:
        raise HTTPException(status_code=400, detail='Search query too long')

    safe_query = re.escape(q)

    # --- Parallel retrieval (text + personalization, always) ---
    async def fetch_name_matches():
        return await db.foods.find(
            {'name': {'$regex': safe_query, '$options': 'i'}},
            {'_id': 0, 'embedding': 0}
        ).limit(100).to_list(None)

    async def fetch_ingredient_matches():
        return await db.foods.find(
            {'$text': {'$search': q}},
            {'_id': 0, 'embedding': 0, 'score': {'$meta': 'textScore'}}
        ).sort([('score', {'$meta': 'textScore'})]).limit(100).to_list(None)

    async def fetch_user_favorites():
        if not user_id:
            return set()
        docs = await db.favorites.find(
            {'user_id': user_id}, {'_id': 0, 'rec_num': 1}
        ).to_list(None)
        return {d['rec_num'] for d in docs}

    async def fetch_intake_counts():
        if not user_id:
            return {}
        pipeline = [
            {'$match': {'user_id': user_id}},
            {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        ]
        result = {}
        async for doc in db.intake.aggregate(pipeline):
            result[doc['_id']] = doc['count']
        return result

    async def fetch_user_views():
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

    # Build the set of parallel tasks
    tasks = [
        fetch_name_matches(),
        fetch_ingredient_matches(),
        fetch_user_favorites(),
        fetch_intake_counts(),
        fetch_user_views(),
        _get_global_views(),
    ]

    # Only add semantic embedding generation when requested (phase 2 call)
    if semantic:
        tasks.append(_get_query_embedding(q))

    results = await asyncio.gather(*tasks, return_exceptions=True)

    # Unpack text/personalization results (always present)
    name_foods = results[0] if not isinstance(results[0], BaseException) else []
    ingredient_foods = results[1] if not isinstance(results[1], BaseException) else []
    fav_rec_nums = results[2] if not isinstance(results[2], BaseException) else set()
    intake_counts = results[3] if not isinstance(results[3], BaseException) else {}
    user_views = results[4] if not isinstance(results[4], BaseException) else {}
    global_views = results[5] if not isinstance(results[5], BaseException) else {}

    # Unpack semantic query embedding (only when semantic=true)
    query_embedding = None
    if semantic and len(results) > 6:
        qe = results[6]
        if not isinstance(qe, BaseException):
            query_embedding = qe

    # --- Union text candidates ---
    candidate_map = {}  # rec_num -> food dict
    for food in name_foods + ingredient_foods:
        rn = food.get('rec_num')
        if rn and rn not in candidate_map:
            candidate_map[rn] = food

    # --- Semantic re-ranking: fetch embeddings only for text-matched candidates ---
    has_semantic = query_embedding is not None and candidate_map
    if has_semantic:
        import numpy as np
        candidate_rns = list(candidate_map.keys())
        embed_rec_nums, embed_matrix = await _get_candidate_embeddings(candidate_rns)
        if embed_matrix is not None:
            q_vec = np.asarray(query_embedding, dtype=np.float32)
            norms = np.linalg.norm(embed_matrix, axis=1) * np.linalg.norm(q_vec)
            norms[norms == 0] = 1.0
            sims = embed_matrix @ q_vec / norms
            for i, rn in enumerate(embed_rec_nums):
                if rn in candidate_map:
                    candidate_map[rn]['embedding'] = embed_matrix[i].tolist()

    # --- Rank ---
    ranked = rank_search_results(
        candidates=list(candidate_map.values()),
        query=q,
        query_embedding=query_embedding,
        fav_rec_nums=fav_rec_nums,
        intake_counts=intake_counts,
        user_views=user_views,
        global_views=global_views,
    )

    # --- Location lookup (batch hall names) ---
    rec_nums = [f['rec_num'] for f in ranked]
    if rec_nums:
        menu_entries = await db.menus.find(
            {'rec_num': {'$in': rec_nums}},
            {'_id': 0, 'rec_num': 1, 'station': 1, 'dining_hall_id': 1}
        ).sort('date', -1).to_list(None)

        hall_ids = {e.get('dining_hall_id', '') for e in menu_entries} - {''}
        hall_names = {}
        if hall_ids:
            hall_docs = await db.dining_halls.find(
                {'hall_id': {'$in': list(hall_ids)}}, {'_id': 0, 'hall_id': 1, 'name': 1}
            ).to_list(None)
            hall_names = {d['hall_id']: d['name'] for d in hall_docs}

        location_map = {}
        for entry in menu_entries:
            rn = entry['rec_num']
            if rn not in location_map:
                hall_id = entry.get('dining_hall_id', '')
                location_map[rn] = {
                    'station': entry.get('station', ''),
                    'dining_hall_id': hall_id,
                    'dining_hall_name': hall_names.get(hall_id, ''),
                }
        for food in ranked:
            loc = location_map.get(food['rec_num'], {})
            food['station'] = loc.get('station', '')
            food['dining_hall_id'] = loc.get('dining_hall_id', '')
            food['dining_hall_name'] = loc.get('dining_hall_name', '')
    else:
        for food in ranked:
            food['station'] = ''
            food['dining_hall_id'] = ''
            food['dining_hall_name'] = ''

    return {'success': True, 'query': q, 'count': len(ranked), 'has_semantic': has_semantic, 'data': ranked}


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
    allowed_sources = {'home', 'station', 'search', 'profile_favorites', 'tracker', 'similar'}
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


@router.post('/api/backfill-similar')
async def backfill_similar(_: None = Depends(require_admin)):
    def _run():
        from embeddings import backfill_all_similar
        from pymongo import MongoClient
        sync_client = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
        sync_db = sync_client.get_default_database()
        count = backfill_all_similar(sync_db)
        print(f"Backfilled similar foods for {count} items")
        sync_client.close()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'backfill started in background'}


@router.post('/api/backfill-frequency')
async def backfill_frequency(_: None = Depends(require_admin)):
    def _run():
        from pymongo import MongoClient, UpdateOne
        sync_client = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
        sync_db = sync_client.get_default_database()

        entries = list(sync_db.menus.find({'frequency': {'$exists': False}}, {'rec_num': 1, 'station': 1, 'dining_hall_id': 1, 'date': 1, '_id': 1}))
        ops = []
        seen = {}
        for entry in entries:
            key = (entry['rec_num'], entry['station'], entry['dining_hall_id'])
            if key not in seen:
                seen[key] = len(sync_db.menus.distinct('date', {
                    'rec_num': entry['rec_num'],
                    'station': entry['station'],
                    'dining_hall_id': entry['dining_hall_id'],
                }))
            ops.append(UpdateOne({'_id': entry['_id']}, {'$set': {'frequency': seen[key]}}))

        if ops:
            sync_db.menus.bulk_write(ops, ordered=False)
        print(f"Backfilled frequency for {len(ops)} menu entries")
        sync_client.close()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'frequency backfill started in background'}


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
        'healthy': ['Garden Salad', 'Quinoa Bowl', 'Grilled Chicken Salad', 'Fresh Fruit Cup', 'Smoothie Bowl'],
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
    guest_id = f"guest_{uuid.uuid4().hex}"
    await db.users.insert_one({
        'user_id': guest_id,
        'is_guest': True,
        'created_at': datetime.now().isoformat()
    })
    return {'success': True, 'user_id': guest_id, 'token': _make_token(guest_id)}


@router.post('/api/auth/apple')
@limiter.limit("10/minute")
async def auth_apple(request: Request, body: AppleAuthBody = Body(...)):
    if not body.apple_user_id:
        raise HTTPException(status_code=400, detail='apple_user_id required')

    await db.users.update_one(
        {'apple_user_id': body.apple_user_id},
        {'$setOnInsert': {'apple_user_id': body.apple_user_id, 'created_at': datetime.now().isoformat()}},
        upsert=True
    )
    return {'success': True, 'user_id': body.apple_user_id, 'token': _make_token(body.apple_user_id)}


@router.post('/api/auth/upgrade')
@limiter.limit("10/minute")
async def upgrade_guest(
    request: Request,
    body: AppleAuthBody = Body(...),
    user_id: str = Depends(get_current_user),
):
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


@router.post('/api/auth/refresh')
@limiter.limit("10/minute")
async def refresh_token(request: Request, user_id: str = Depends(get_current_user)):
    return {'success': True, 'token': _make_token(user_id)}


async def _archive_user_data(user_id: str):
    """Anonymize all behavioral data for ML training, then delete the identity."""
    anon_id = 'anon_' + hashlib.sha256(user_id.encode()).hexdigest()[:16]

    for coll in [db.favorites, db.station_favorites, db.preferences, db.intake, db.item_views, db.search_queries]:
        await coll.update_many({'user_id': user_id}, {'$set': {'user_id': anon_id}})

    await db.users.delete_one({'user_id': user_id})


@router.delete('/api/auth/account')
@limiter.limit("5/minute")
async def delete_account(request: Request, user_id: str = Depends(get_current_user)):
    await _archive_user_data(user_id)
    return {'success': True}


# ---------------------------------------------------------------------------
# Favorites
# ---------------------------------------------------------------------------

@router.get('/api/favorites')
@limiter.limit("60/minute")
async def get_favorites(request: Request,user_id: str = Depends(get_current_user)):
    favs = await db.favorites.find({'user_id': user_id}, {'_id': 0}).to_list(None)
    return {'success': True, 'data': favs}


@router.post('/api/favorites')
@limiter.limit("30/minute")
async def add_favorite(request: Request,body: FavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    await db.favorites.update_one(
        {'user_id': user_id, 'rec_num': body.rec_num},
        {'$set': {'user_id': user_id, 'rec_num': body.rec_num, 'name': body.name, 'added_at': datetime.now().isoformat()}},
        upsert=True
    )
    return {'success': True}


@router.delete('/api/favorites')
@limiter.limit("30/minute")
async def remove_favorite(request: Request,body: RemoveFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    await db.favorites.delete_one({'user_id': user_id, 'rec_num': body.rec_num})
    return {'success': True}


# ---------------------------------------------------------------------------
# Station Favorites
# ---------------------------------------------------------------------------

@router.get('/api/station-favorites')
@limiter.limit("60/minute")
async def get_station_favorites(request: Request,user_id: str = Depends(get_current_user)):
    favs = await db.station_favorites.find({'user_id': user_id}, {'_id': 0}).to_list(None)
    return {'success': True, 'data': favs}


@router.post('/api/station-favorites')
@limiter.limit("30/minute")
async def add_station_favorite(request: Request,body: StationFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    await db.station_favorites.update_one(
        {'user_id': user_id, 'station_name': body.station_name},
        {'$set': {'user_id': user_id, 'station_name': body.station_name, 'added_at': datetime.now().isoformat()}},
        upsert=True
    )
    return {'success': True}


@router.delete('/api/station-favorites')
@limiter.limit("30/minute")
async def remove_station_favorite(request: Request,body: StationFavoriteBody = Body(...), user_id: str = Depends(get_current_user)):
    await db.station_favorites.delete_one({'user_id': user_id, 'station_name': body.station_name})
    return {'success': True}


# ---------------------------------------------------------------------------
# Preferences
# ---------------------------------------------------------------------------

@router.get('/api/preferences')
@limiter.limit("30/minute")
async def get_preferences(request: Request,user_id: str = Depends(get_current_user)):
    prefs = await db.preferences.find_one({'user_id': user_id}, {'_id': 0})
    if not prefs:
        prefs = {'user_id': user_id, 'vegetarian': False, 'vegan': False, 'allergens': [], 'cuisine_prefs': []}
    return {'success': True, 'data': prefs}


@router.put('/api/preferences')
@limiter.limit("20/minute")
async def update_preferences(request: Request,body: PreferencesBody = Body(...), user_id: str = Depends(get_current_user)):
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


# ---------------------------------------------------------------------------
# Intake Tracking
# ---------------------------------------------------------------------------

@router.get('/api/intake')
@limiter.limit("60/minute")
async def get_intake(request: Request, date: Optional[str] = Query(default=None), user_id: str = Depends(get_current_user)):
    query: dict = {'user_id': user_id}
    if date:
        query['date'] = date
    items = await db.intake.find(query, {'_id': 0}).to_list(None)
    return {'success': True, 'data': items}


@router.post('/api/intake')
@limiter.limit("30/minute")
async def log_intake(request: Request, body: IntakeBody = Body(...), user_id: str = Depends(get_current_user)):
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


@router.delete('/api/intake')
@limiter.limit("30/minute")
async def remove_intake(request: Request, body: RemoveIntakeBody = Body(...), user_id: str = Depends(get_current_user)):
    if not body.rec_num:
        raise HTTPException(status_code=400, detail='rec_num required')

    query: dict = {'user_id': user_id, 'rec_num': body.rec_num}
    if body.date:
        query['date'] = body.date
    if body.logged_at:
        query['logged_at'] = body.logged_at

    await db.intake.delete_one(query)
    return {'success': True}
