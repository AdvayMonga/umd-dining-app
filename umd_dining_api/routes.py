import asyncio
import hashlib
import hmac
import re
import time
import threading
import uuid
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt as pyjwt
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Body
from pydantic import BaseModel

import requests as sync_requests

from main import db, limiter, SECRET_KEY, ADMIN_SECRET
from scraper import scrape_all_dining_halls, scrape_dining_hall, scrape_full_week, fetch_and_cache_nutrition, get_nutrition_info, db as sync_db
from ranker import rank_items
from search_ranker import rank_search_results
from embeddings import generate_embedding_async

router = APIRouter()

# --- Bounded thread pool for background nutrition fetches ---
_nutrition_executor = ThreadPoolExecutor(max_workers=4)
_nutrition_in_flight: set = set()
_nutrition_lock = threading.Lock()

# --- Admin job locks (prevent concurrent execution) ---
_admin_locks = {
    'scrape': threading.Lock(),
    'scrape_week': threading.Lock(),
    'embed': threading.Lock(),
    'similar': threading.Lock(),
    'frequency': threading.Lock(),
    'cuisine': threading.Lock(),
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _ensure_string(value, field_name='field'):
    if not isinstance(value, str):
        raise HTTPException(status_code=400, detail=f'{field_name} must be a string')
    return value


def _today_str() -> str:
    return datetime.now().strftime('%-m/%-d/%Y')


async def _resolve_availability(rec_nums: list, today: Optional[str] = None) -> dict:
    """For each rec_num, return today's location if available, else next-day location
    within the 7-day window, else mark unavailable_this_week.

    Returns: {rec_num: {available_today, station, dining_hall_id, dining_hall_name,
                        next_available_date, unavailable_this_week}}
    """
    if not rec_nums:
        return {}
    today = today or _today_str()

    today_entries = await db.menus.find(
        {'rec_num': {'$in': rec_nums}, 'date': today},
        {'_id': 0, 'rec_num': 1, 'station': 1, 'dining_hall_id': 1}
    ).to_list(None)
    today_loc = {}
    for e in today_entries:
        rn = e['rec_num']
        if rn not in today_loc:
            today_loc[rn] = e

    missing = [rn for rn in rec_nums if rn not in today_loc]
    next_loc = {}
    if missing:
        future_entries = await db.menus.find(
            {'rec_num': {'$in': missing}},
            {'_id': 0, 'rec_num': 1, 'station': 1, 'dining_hall_id': 1, 'date': 1}
        ).to_list(None)
        try:
            today_dt = datetime.strptime(today, '%m/%d/%Y').date()
        except ValueError:
            today_dt = datetime.now().date()
        for e in future_entries:
            try:
                d = datetime.strptime(e['date'], '%m/%d/%Y').date()
            except ValueError:
                continue
            if d < today_dt:
                continue
            rn = e['rec_num']
            cur = next_loc.get(rn)
            if cur is None or d < cur['_d']:
                next_loc[rn] = {**e, '_d': d}

    hall_ids = set()
    for e in today_loc.values():
        if e.get('dining_hall_id'):
            hall_ids.add(e['dining_hall_id'])
    for e in next_loc.values():
        if e.get('dining_hall_id'):
            hall_ids.add(e['dining_hall_id'])

    hall_names = {}
    if hall_ids:
        hall_docs = await db.dining_halls.find(
            {'hall_id': {'$in': list(hall_ids)}}, {'_id': 0, 'hall_id': 1, 'name': 1}
        ).to_list(None)
        hall_names = {d['hall_id']: d['name'] for d in hall_docs}

    result = {}
    for rn in rec_nums:
        if rn in today_loc:
            e = today_loc[rn]
            hid = e.get('dining_hall_id', '')
            result[rn] = {
                'available_today': True,
                'station': e.get('station', ''),
                'dining_hall_id': hid,
                'dining_hall_name': hall_names.get(hid, ''),
                'next_available_date': None,
                'unavailable_this_week': False,
            }
        elif rn in next_loc:
            e = next_loc[rn]
            hid = e.get('dining_hall_id', '')
            result[rn] = {
                'available_today': False,
                'station': e.get('station', ''),
                'dining_hall_id': hid,
                'dining_hall_name': hall_names.get(hid, ''),
                'next_available_date': e.get('date'),
                'unavailable_this_week': False,
            }
        else:
            result[rn] = {
                'available_today': False,
                'station': '',
                'dining_hall_id': '',
                'dining_hall_name': '',
                'next_available_date': None,
                'unavailable_this_week': True,
            }
    return result


# --- Trending cache (global, 5-min TTL) ---
_trending_cache: dict = {'data': set(), 'expires': 0}

# --- Guest response cache (5-min TTL) ---
_guest_menu_cache: dict = {}  # {cache_key: {'data': response_dict, 'expires': float}}

async def _get_trending():
    now = time.time()
    if now < _trending_cache['expires']:
        return _trending_cache['data']
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    pipeline = [
        {'$match': {'added_at': {'$gte': cutoff}}},
        {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        {'$sort': {'count': -1}},
        {'$limit': 50}
    ]
    result = set()
    async for doc in db.favorites.aggregate(pipeline):
        result.add(doc['_id'])
    _trending_cache.update({'data': result, 'expires': now + 300})
    return result


# --- Trending searches cache (5-min TTL) ---
_trending_searches_cache: dict = {'data': [], 'expires': 0}

async def _get_trending_searches():
    now = time.time()
    if now < _trending_searches_cache['expires']:
        return _trending_searches_cache['data']
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    pipeline = [
        {'$match': {'result_count': {'$gt': 0}, 'timestamp': {'$gte': cutoff}}},
        {'$group': {'_id': {'$toLower': '$query'}, 'count': {'$sum': 1}}},
        {'$sort': {'count': -1}},
        {'$limit': 10}
    ]
    result = []
    async for doc in db.search_queries.aggregate(pipeline):
        if doc['_id'] and len(doc['_id']) >= 2:
            result.append(doc['_id'])
    _trending_searches_cache.update({'data': result, 'expires': now + 300})
    return result


# --- Global view counts cache (5-min TTL) ---
_global_views_cache: dict = {'data': {}, 'expires': 0}

async def _get_global_views():
    now = time.time()
    if now < _global_views_cache['expires']:
        return _global_views_cache['data']
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    pipeline = [
        {'$match': {'timestamp': {'$gte': cutoff}}},
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
        user_id = payload['sub']
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail='token expired')
    except pyjwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail='invalid token')
    exists = await db.users.find_one(
        {'$or': [{'user_id': user_id}, {'apple_user_id': user_id}]},
        {'_id': 1}
    )
    if not exists:
        raise HTTPException(status_code=401, detail='user not found')
    return user_id


async def get_optional_user(authorization: str = Header(default='')) -> Optional[str]:
    if not authorization.startswith('Bearer '):
        return None
    try:
        payload = pyjwt.decode(authorization[7:], SECRET_KEY, algorithms=['HS256'])
        return payload['sub']
    except pyjwt.InvalidTokenError:
        return None


async def require_admin(x_admin_key: str = Header(default='')):
    if not ADMIN_SECRET:
        raise HTTPException(status_code=500, detail='server misconfigured')
    if x_admin_key != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail='unauthorized')


def _make_token(user_id: str) -> str:
    return pyjwt.encode(
        {'sub': user_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
        SECRET_KEY,
        algorithm='HS256'
    )


# --- Apple Sign In token verification ---
_apple_jwks_cache: dict = {'keys': None, 'expires': 0}

def _get_apple_public_keys():
    now = time.time()
    if _apple_jwks_cache['keys'] and now < _apple_jwks_cache['expires']:
        return _apple_jwks_cache['keys']
    resp = sync_requests.get('https://appleid.apple.com/auth/keys', timeout=10)
    resp.raise_for_status()
    keys = resp.json()['keys']
    _apple_jwks_cache.update({'keys': keys, 'expires': now + 3600})
    return keys

def _verify_apple_token(identity_token: str) -> str:
    """Verify Apple identity token and return the subject (user ID)."""
    from jwt.algorithms import RSAAlgorithm

    try:
        header = pyjwt.get_unverified_header(identity_token)
    except pyjwt.DecodeError:
        raise HTTPException(status_code=401, detail='invalid identity token')

    apple_keys = _get_apple_public_keys()
    matching = [k for k in apple_keys if k['kid'] == header.get('kid')]
    if not matching:
        _apple_jwks_cache['expires'] = 0
        apple_keys = _get_apple_public_keys()
        matching = [k for k in apple_keys if k['kid'] == header.get('kid')]
        if not matching:
            raise HTTPException(status_code=401, detail='unknown signing key')

    public_key = RSAAlgorithm.from_jwk(matching[0])

    try:
        payload = pyjwt.decode(
            identity_token,
            public_key,
            algorithms=['RS256'],
            audience='umddining.UMD-Dining',
            issuer='https://appleid.apple.com',
        )
    except pyjwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail='apple token expired')
    except pyjwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f'apple token invalid: {str(e)}')

    return payload['sub']


# ---------------------------------------------------------------------------
# Pydantic models for request bodies
# ---------------------------------------------------------------------------

class AppleAuthBody(BaseModel):
    apple_user_id: str = ''
    identity_token: str

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
    preferred_dining_halls: list[str] = []

class AnnouncementBody(BaseModel):
    title: str = ''
    message: str = ''
    active: bool = True

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
<a href="https://apps.apple.com/us/app/umd-dining/id6761645776" target="_blank" style="display:inline-block;margin-bottom:28px"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height:44px"></a>
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
    halal: bool = Query(default=False),
    high_protein: bool = Query(default=False),
    allergens: list[str] = Query(default=[]),
):
    if not date:
        raise HTTPException(status_code=400, detail='date required')

    # --- Guest response cache ---
    is_guest = user_id is None
    if is_guest:
        cache_key = (date, tuple(sorted(dining_hall_ids)), vegetarian, vegan, halal, high_protein, tuple(sorted(allergens)))
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
    has_filters = vegetarian or vegan or halal or high_protein or allergens
    if has_filters:
        filtered_entries = []
        for entry in menu_entries:
            icons = entry.get('dietary_icons', [])
            if vegan and 'vegan' not in icons:
                continue
            if vegetarian and 'vegetarian' not in icons:
                continue
            if halal and 'HalalFriendly' not in icons:
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

    # --- Phase 3: Fetch embeddings for favorites and/or cuisine centroids ---
    fav_embeddings = []
    has_cuisine_prefs = user_id and user_prefs.get('cuisine_prefs')

    if user_id and fav_rec_nums:
        fav_food_docs = await db.foods.find(
            {'rec_num': {'$in': list(fav_rec_nums)}, 'embedding': {'$exists': True}},
            {'embedding': 1, '_id': 0}
        ).to_list(None)
        fav_embeddings = [doc['embedding'] for doc in fav_food_docs if doc.get('embedding')]

    # Fetch menu item embeddings if we have favorites OR cuisine prefs (needed for similarity)
    if fav_embeddings or has_cuisine_prefs:
        menu_emb_docs = await db.foods.find(
            {'rec_num': {'$in': rec_nums}, 'embedding': {'$exists': True}},
            {'rec_num': 1, 'embedding': 1, '_id': 0}
        ).to_list(None)
        for doc in menu_emb_docs:
            if doc.get('embedding') and doc['rec_num'] in foods:
                foods[doc['rec_num']]['embedding'] = doc['embedding']

    # Blend cuisine centroids: full strength at 0 favs, linearly decreasing to 0.5 at 20+ favs
    if has_cuisine_prefs:
        cuisine_docs = await db.cuisine_embeddings.find(
            {'cuisine': {'$in': user_prefs['cuisine_prefs']}},
            {'embedding': 1, 'cuisine': 1, '_id': 0}
        ).to_list(None)
        cuisine_embs = [doc['embedding'] for doc in cuisine_docs if doc.get('embedding')]
        if cuisine_embs:
            import numpy as np
            num_favs = len(fav_embeddings)
            weight = 1.0 - 0.5 * min(num_favs, 20) / 20  # 1.0 → 0.5 over 0–20 favs
            weighted = [(np.asarray(e, dtype=np.float32) * weight).tolist() for e in cuisine_embs]
            fav_embeddings = fav_embeddings + weighted

    preferred_halls = user_prefs.get('preferred_dining_halls', []) if user_prefs else []

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
        preferred_halls=preferred_halls,
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
    if not query:
        raise HTTPException(status_code=400, detail='at least one filter (date or dining_hall_id) required')

    menu_entries = await db.menus.find(query, {'_id': 0}).to_list(5000)
    rec_nums = [entry['rec_num'] for entry in menu_entries]
    food_docs = await db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0}).to_list(5000)
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
        with _nutrition_lock:
            if rec_num not in _nutrition_in_flight:
                _nutrition_in_flight.add(rec_num)
                def _fetch(rn=rec_num):
                    try:
                        fetch_and_cache_nutrition(rn)
                    finally:
                        with _nutrition_lock:
                            _nutrition_in_flight.discard(rn)
                _nutrition_executor.submit(_fetch)

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

    # Get dietary_icons from menus collection (reliable source for allergen info)
    menu_entry = await db.menus.find_one({'rec_num': rec_num}, {'dietary_icons': 1, '_id': 0})
    dietary_icons = menu_entry.get('dietary_icons', []) if menu_entry else []

    availability = (await _resolve_availability([rec_num])).get(rec_num)

    return {
        'success': True,
        'data': {
            'rec_num': food['rec_num'],
            'name': food.get('name', ''),
            'nutrition': food.get('nutrition', {}),
            'allergens': food.get('allergens', ''),
            'ingredients': food.get('ingredients', ''),
            'next_available': next_available,
            'dietary_icons': dietary_icons,
            'availability': availability,
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

    # Today-first availability
    availability = await _resolve_availability(similar_rec_nums)

    # Pull dietary_icons / meal_period from any recent entry (most-recent-wins) for display
    menu_entries = await db.menus.find(
        {'rec_num': {'$in': similar_rec_nums}},
        {'_id': 0, 'rec_num': 1, 'dietary_icons': 1, 'date': 1, 'meal_period': 1}
    ).sort('date', -1).to_list(None)
    extras = {}
    for entry in menu_entries:
        rn = entry['rec_num']
        if rn not in extras:
            extras[rn] = {
                'dietary_icons': entry.get('dietary_icons', []),
                'date': entry.get('date', ''),
                'meal_period': entry.get('meal_period', ''),
            }

    data = []
    for rn in similar_rec_nums:
        f = food_map.get(rn, {})
        info = availability.get(rn, {
            'available_today': False, 'station': '', 'dining_hall_id': '',
            'dining_hall_name': '', 'next_available_date': None, 'unavailable_this_week': True,
        })
        ex = extras.get(rn, {})
        data.append({
            'name': f.get('name', ''),
            'rec_num': rn,
            'station': info['station'],
            'dining_hall_id': info['dining_hall_id'],
            'dining_hall_name': info['dining_hall_name'],
            'availability': info,
            'date': ex.get('date', ''),
            'meal_period': ex.get('meal_period', ''),
            'dietary_icons': ex.get('dietary_icons', []),
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

    # --- Resolve availability up front so the ranker can tier today's items ---
    candidate_rec_nums = list(candidate_map.keys())
    availability = await _resolve_availability(candidate_rec_nums) if candidate_rec_nums else {}
    available_today_rec_nums = {rn for rn, info in availability.items() if info.get('available_today')}

    # --- Rank ---
    ranked = rank_search_results(
        candidates=list(candidate_map.values()),
        query=q,
        query_embedding=query_embedding,
        fav_rec_nums=fav_rec_nums,
        intake_counts=intake_counts,
        user_views=user_views,
        global_views=global_views,
        available_today_rec_nums=available_today_rec_nums,
    )

    # --- Attach location info (reuses availability fetched above) ---
    for food in ranked:
        info = availability.get(food['rec_num'], {
            'available_today': False, 'station': '', 'dining_hall_id': '',
            'dining_hall_name': '', 'next_available_date': None, 'unavailable_this_week': True,
        })
        food['station'] = info['station']
        food['dining_hall_id'] = info['dining_hall_id']
        food['dining_hall_name'] = info['dining_hall_name']
        food['availability'] = info

    return {'success': True, 'query': q, 'count': len(ranked), 'has_semantic': has_semantic, 'data': ranked}


@router.get('/api/availability')
@limiter.limit("30/minute")
async def get_availability(request: Request, rec_nums: str = Query(default='')):
    if not rec_nums:
        return {'success': True, 'data': {}}
    parts = [p.strip() for p in rec_nums.split(',') if p.strip()]
    if len(parts) > 200:
        raise HTTPException(status_code=400, detail='too many rec_nums (max 200)')
    data = await _resolve_availability(parts)
    return {'success': True, 'data': data}


@router.get('/api/trending-searches')
@limiter.limit("30/minute")
async def get_trending_searches(request: Request):
    data = await _get_trending_searches()
    return {'success': True, 'data': data}


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
        'timestamp': datetime.now(timezone.utc),
    })
    return {'success': True}


@router.post('/api/track/search-query')
@limiter.limit("60/minute")
async def track_search_query(
    request: Request,
    body: SearchQueryBody,
    user_id: Optional[str] = Depends(get_optional_user),
):
    if len(body.query) > 200 or body.result_count == 0:
        return {'success': True}
    await db.search_queries.insert_one({
        'user_id': user_id,
        'query': body.query,
        'result_count': body.result_count,
        'timestamp': datetime.now(timezone.utc),
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
    if not _admin_locks['scrape'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='scrape already running')
    scrape_date = date or datetime.now().strftime('%-m/%-d/%Y')
    def _run():
        try:
            if dining_hall_id:
                scrape_dining_hall(dining_hall_id, scrape_date)
            else:
                scrape_all_dining_halls(scrape_date)
        finally:
            _admin_locks['scrape'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'date': scrape_date, 'status': 'scrape started'}


@router.post('/api/scrape-week')
async def scrape_week(_: None = Depends(require_admin)):
    if not _admin_locks['scrape_week'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='scrape-week already running')
    def _run():
        try:
            scrape_full_week()
        finally:
            _admin_locks['scrape_week'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'scrape started'}


@router.post('/api/embed-missing')
async def embed_missing(_: None = Depends(require_admin)):
    if not _admin_locks['embed'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='embedding already running')
    def _run():
        try:
            from embeddings import generate_and_store_embedding
            import time as _time
            for food in sync_db.foods.find({'embedding': {'$exists': False}}, {'_id': 0}):
                try:
                    generate_and_store_embedding(sync_db, food['rec_num'], food)
                    _time.sleep(0.1)
                except Exception as e:
                    print(f"Embedding failed for {food['rec_num']}: {e}")
        finally:
            _admin_locks['embed'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'embedding started in background'}


@router.post('/api/backfill-similar')
async def backfill_similar(_: None = Depends(require_admin)):
    if not _admin_locks['similar'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='backfill-similar already running')
    def _run():
        try:
            from embeddings import backfill_all_similar
            count = backfill_all_similar(sync_db)
            print(f"Backfilled similar foods for {count} items")
        finally:
            _admin_locks['similar'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'backfill started in background'}


@router.post('/api/backfill-frequency')
async def backfill_frequency(_: None = Depends(require_admin)):
    if not _admin_locks['frequency'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='backfill-frequency already running')
    def _run():
        try:
            from pymongo import UpdateOne
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
        finally:
            _admin_locks['frequency'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'frequency backfill started in background'}


@router.post('/api/cuisine-embeddings/generate')
async def generate_cuisine_embeddings(_: None = Depends(require_admin)):
    if not _admin_locks['cuisine'].acquire(blocking=False):
        raise HTTPException(status_code=409, detail='cuisine embedding already running')
    from embeddings import generate_embedding, compute_centroid
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

    def _run():
        try:
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
        finally:
            _admin_locks['cuisine'].release()
    threading.Thread(target=_run, daemon=False).start()
    return {'success': True, 'status': 'cuisine embedding started in background'}


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
        'created_at': datetime.now(timezone.utc)
    })
    return {'success': True, 'user_id': guest_id, 'token': _make_token(guest_id)}


@router.post('/api/auth/apple')
@limiter.limit("10/minute")
async def auth_apple(request: Request, body: AppleAuthBody = Body(...)):
    apple_user_id = _verify_apple_token(body.identity_token)

    await db.users.update_one(
        {'apple_user_id': apple_user_id},
        {'$setOnInsert': {'apple_user_id': apple_user_id, 'created_at': datetime.now(timezone.utc)}},
        upsert=True
    )
    return {'success': True, 'user_id': apple_user_id, 'token': _make_token(apple_user_id)}


@router.post('/api/auth/upgrade')
@limiter.limit("10/minute")
async def upgrade_guest(
    request: Request,
    body: AppleAuthBody = Body(...),
    user_id: str = Depends(get_current_user),
):
    apple_user_id = _verify_apple_token(body.identity_token)
    if not user_id.startswith('guest_'):
        raise HTTPException(status_code=400, detail='not a guest account')

    await db.users.update_one(
        {'apple_user_id': apple_user_id},
        {'$setOnInsert': {'apple_user_id': apple_user_id, 'created_at': datetime.now(timezone.utc)}},
        upsert=True
    )

    # Migrate all user data
    for coll in [db.favorites, db.station_favorites, db.preferences, db.intake]:
        await coll.update_many({'user_id': user_id}, {'$set': {'user_id': apple_user_id}})

    await db.users.delete_one({'user_id': user_id})

    return {'success': True, 'user_id': apple_user_id, 'token': _make_token(apple_user_id)}


@router.post('/api/auth/refresh')
@limiter.limit("10/minute")
async def refresh_token(request: Request, user_id: str = Depends(get_current_user)):
    return {'success': True, 'token': _make_token(user_id)}


async def _archive_user_data(user_id: str):
    """Anonymize all behavioral data for ML training, then delete the identity."""
    anon_id = 'anon_' + hmac.new(SECRET_KEY.encode(), user_id.encode(), hashlib.sha256).hexdigest()[:16]

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
        prefs = {'user_id': user_id, 'vegetarian': False, 'vegan': False, 'allergens': [], 'cuisine_prefs': [], 'preferred_dining_halls': []}
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
            'preferred_dining_halls': body.preferred_dining_halls,
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


# ---------------------------------------------------------------------------
# Announcements
# ---------------------------------------------------------------------------

@router.get('/api/announcement')
@limiter.limit("30/minute")
async def get_announcement(request: Request):
    doc = await db.announcements.find_one({}, {'_id': 0})
    if not doc or not doc.get('active', False):
        return {'success': True, 'data': {'title': '', 'message': '', 'active': False}}
    return {'success': True, 'data': doc}


@router.put('/api/announcement')
@limiter.limit("10/minute")
async def update_announcement(request: Request, body: AnnouncementBody = Body(...), _: str = Depends(require_admin)):
    await db.announcements.update_one(
        {},
        {'$set': {'title': body.title, 'message': body.message, 'active': body.active}},
        upsert=True
    )
    return {'success': True}


@router.post('/api/admin/backfill-nutrition')
@limiter.limit("5/minute")
async def backfill_nutrition(request: Request, _: str = Depends(require_admin)):
    """Re-scrape nutrition for foods with missing or zero calories."""
    import asyncio

    # Find foods with no nutrition, no calories, or zero calories
    query = {
        '$or': [
            {'nutrition_fetched': False},
            {'nutrition_fetched': {'$exists': False}},
            {'nutrition.Calories': {'$exists': False}},
            {'nutrition.Calories': ''},
            {'nutrition.Calories': '0'},
            {'nutrition': {}},
        ]
    }
    cursor = db.foods.find(query, {'rec_num': 1, 'name': 1, '_id': 0})
    foods = await cursor.to_list(length=None)

    fixed = 0
    failed = 0
    for food in foods:
        rec_num = food['rec_num']
        try:
            nutrition_data = await asyncio.to_thread(get_nutrition_info, rec_num)
            calories = nutrition_data.get('Calories', '')
            if calories and calories != '0':
                update = {
                    'nutrition_fetched': True,
                    'nutrition': {k: v for k, v in nutrition_data.items() if k not in ('ingredients', 'allergens')},
                    'allergens': nutrition_data.get('allergens', ''),
                    'ingredients': nutrition_data.get('ingredients', ''),
                }
                await db.foods.update_one({'rec_num': rec_num}, {'$set': update})
                fixed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"Backfill failed for {rec_num}: {e}")
            failed += 1

    return {'success': True, 'fixed': fixed, 'failed': failed, 'total_attempted': len(foods)}
