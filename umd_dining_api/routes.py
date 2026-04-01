from flask import jsonify, request, g
from app import app, db, limiter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from functools import wraps
import re
import time
import threading
import os
import jwt as pyjwt
from scraper import scrape_all_dining_halls, scrape_dining_hall, scrape_full_week, fetch_and_cache_nutrition
from ranker import rank_items

# Thread pool for parallelizing DB queries within a request
_db_pool = ThreadPoolExecutor(max_workers=8)


def _ensure_string(value, field_name='field'):
    """Reject non-string values to prevent NoSQL operator injection from JSON bodies."""
    if not isinstance(value, str):
        raise ValueError(f'{field_name} must be a string')
    return value


# --- Trending cache (global across all users, refreshed every 5 min) ---
_trending_cache = {'data': set(), 'expires': 0}

def _get_trending():
    now = time.time()
    if now < _trending_cache['expires']:
        return _trending_cache['data']
    pipeline = [
        {'$group': {'_id': '$rec_num', 'count': {'$sum': 1}}},
        {'$sort': {'count': -1}},
        {'$limit': 50}
    ]
    result = {doc['_id'] for doc in db.favorites.aggregate(pipeline)}
    _trending_cache.update({'data': result, 'expires': now + 300})
    return result


# --- Auth decorators ---

def require_auth(f):
    """Validates Authorization: Bearer <jwt> and sets g.user_id."""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get('Authorization', '')
        if not auth.startswith('Bearer '):
            return jsonify({'error': 'unauthorized'}), 401
        token = auth[7:]
        try:
            payload = pyjwt.decode(token, os.environ['SECRET_KEY'], algorithms=['HS256'])
            g.user_id = payload['sub']
        except pyjwt.ExpiredSignatureError:
            return jsonify({'error': 'token expired'}), 401
        except pyjwt.InvalidTokenError:
            return jsonify({'error': 'invalid token'}), 401
        return f(*args, **kwargs)
    return decorated


def _require_admin(f):
    """Validates X-Admin-Key header against ADMIN_SECRET env var."""
    @wraps(f)
    def decorated(*args, **kwargs):
        secret = os.environ.get('ADMIN_SECRET')
        if secret and request.headers.get('X-Admin-Key') != secret:
            return jsonify({'error': 'unauthorized'}), 403
        return f(*args, **kwargs)
    return decorated


# --- Public endpoints ---

@app.route('/')
def home():
    return jsonify({
        'message': 'UMD Dining API is running!',
        'version': '2.0',
        'endpoints': {
            'dining_halls': '/api/dining-halls',
            'available_dates': '/api/available-dates',
            'menu': '/api/menu?date=...&dining_hall_id=...',
            'nutrition': '/api/nutrition?rec_num=...',
            'search': '/api/search?q=...',
            'scrape': 'POST /api/scrape'
        }
    })

@app.get('/api/dining-halls')
def get_dining_halls():
    try:
        halls = list(db.dining_halls.find({}, {'_id': 0}))
        return jsonify({
            'success': True,
            'count': len(halls),
            'data': halls
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/available-dates')
def get_available_dates():
    try:
        dates = db.menus.distinct("date")
        return jsonify({
            'success': True,
            'count': len(dates),
            'data': sorted(dates)
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/ranked-menu')
@limiter.limit("60 per minute")
def get_ranked_menu():
    try:
        date = request.args.get('date')
        dining_hall_ids = request.args.getlist('dining_hall_ids') or ['19', '51', '16']

        # Accept user_id from JWT only — no query param fallback to prevent user_id enumeration
        auth = request.headers.get('Authorization', '')
        user_id = None
        if auth.startswith('Bearer '):
            try:
                payload = pyjwt.decode(auth[7:], os.environ['SECRET_KEY'], algorithms=['HS256'])
                user_id = payload['sub']
            except pyjwt.InvalidTokenError:
                pass

        if not date:
            return jsonify({'success': False, 'error': 'date required'}), 400

        # --- Phase 1: Parallel DB queries (all independent reads) ---
        def fetch_menus():
            return list(db.menus.find(
                {'date': date, 'dining_hall_id': {'$in': dining_hall_ids}},
                {'_id': 0}
            ))

        def fetch_user_favs():
            if not user_id:
                return set()
            return {fav['rec_num'] for fav in db.favorites.find({'user_id': user_id}, {'rec_num': 1, '_id': 0})}

        def fetch_user_stations():
            if not user_id:
                return set()
            return {sf['station_name'] for sf in db.station_favorites.find({'user_id': user_id}, {'station_name': 1, '_id': 0})}

        def fetch_user_prefs():
            if not user_id:
                return {}
            return db.preferences.find_one({'user_id': user_id}, {'_id': 0}) or {}

        f_menus = _db_pool.submit(fetch_menus)
        f_favs = _db_pool.submit(fetch_user_favs)
        f_stations = _db_pool.submit(fetch_user_stations)
        f_prefs = _db_pool.submit(fetch_user_prefs)

        menu_entries = f_menus.result()
        fav_rec_nums = f_favs.result()
        fav_stations = f_stations.result()
        user_prefs = f_prefs.result()

        # --- Phase 2: Fetch foods (exclude embeddings — they're huge and only needed for similarity) ---
        rec_nums = [e['rec_num'] for e in menu_entries]
        foods = {f['rec_num']: f for f in db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0, 'embedding': 0})}

        # --- Phase 3: Fetch embeddings only if user has favorites (for similarity scoring) ---
        fav_embeddings = []
        if user_id and fav_rec_nums:
            fav_food_docs = db.foods.find(
                {'rec_num': {'$in': list(fav_rec_nums)}, 'embedding': {'$exists': True}},
                {'embedding': 1, '_id': 0}
            )
            fav_embeddings = [doc['embedding'] for doc in fav_food_docs if doc.get('embedding')]

            # If user has favorites, also fetch embeddings for today's menu items (for cosine scoring)
            if fav_embeddings:
                menu_embeddings = {f['rec_num']: f['embedding'] for f in db.foods.find(
                    {'rec_num': {'$in': rec_nums}, 'embedding': {'$exists': True}},
                    {'rec_num': 1, 'embedding': 1, '_id': 0}
                ) if f.get('embedding')}
                # Merge embeddings into foods dict for the ranker
                for rn, emb in menu_embeddings.items():
                    if rn in foods:
                        foods[rn]['embedding'] = emb

        # Cold-start: if <3 real favorites, fall back to cuisine preference embeddings
        if user_id and len(fav_embeddings) < 3 and user_prefs.get('cuisine_prefs'):
            cuisine_docs = db.cuisine_embeddings.find(
                {'cuisine': {'$in': user_prefs['cuisine_prefs']}},
                {'embedding': 1, '_id': 0}
            )
            cuisine_embs = [doc['embedding'] for doc in cuisine_docs if doc.get('embedding')]
            if cuisine_embs:
                fav_embeddings = cuisine_embs

        # Trending: cached globally, refreshed every 5 min
        popular_rec_nums = _get_trending()

        result = rank_items(
            menu_entries=menu_entries,
            foods=foods,
            fav_rec_nums=fav_rec_nums,
            fav_stations=fav_stations,
            user_prefs=user_prefs,
            popular_rec_nums=popular_rec_nums,
            date_seed=date,
            fav_embeddings=fav_embeddings,
        )

        return jsonify({'success': True, 'count': len(result), 'data': result})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/menu')
def get_menu():
    try:
        query = {}
        dining_hall_id = request.args.get('dining_hall_id')
        date = request.args.get('date')
        if dining_hall_id:
            query['dining_hall_id'] = dining_hall_id
        if date:
            query['date'] = date

        menu_entries = list(db.menus.find(query, {'_id': 0}))
        rec_nums = [entry['rec_num'] for entry in menu_entries]
        foods = {f['rec_num']: f for f in db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0})}

        items = []
        for entry in menu_entries:
            food = foods.get(entry['rec_num'], {})
            item = {
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
            }
            items.append(item)

        return jsonify({'success': True, 'count': len(items), 'filters': query, 'data': items})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/nutrition')
@limiter.limit("60 per minute")
def get_nutrition():
    try:
        rec_num = request.args.get('rec_num')
        if not rec_num:
            return jsonify({'success': False, 'error': 'rec_num parameter required'}), 400

        food = fetch_and_cache_nutrition(rec_num)
        if not food:
            return jsonify({'success': False, 'error': 'Food not found'}), 404

        return jsonify({
            'success': True,
            'data': {
                'rec_num': food['rec_num'],
                'name': food.get('name', ''),
                'nutrition': food.get('nutrition', {}),
                'allergens': food.get('allergens', ''),
                'ingredients': food.get('ingredients', ''),
            }
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/search')
@limiter.limit("30 per minute")
def search_menu():
    try:
        search_query = request.args.get('q', '')
        if not search_query:
            return jsonify({'success': False, 'error': 'Search query required'}), 400
        if len(search_query) > 100:
            return jsonify({'success': False, 'error': 'Search query too long'}), 400

        # Escape regex special chars to prevent ReDoS and operator injection
        safe_query = re.escape(search_query)

        foods = list(db.foods.find(
            {'name': {'$regex': safe_query, '$options': 'i'}},
            {'_id': 0, 'embedding': 0}
        ).limit(50))

        return jsonify({'success': True, 'query': search_query, 'count': len(foods), 'data': foods})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# --- Admin endpoints ---

@app.post('/api/scrape')
@_require_admin
def scrape():
    date = request.args.get('date', datetime.now().strftime('%-m/%-d/%Y'))
    dining_hall_id = request.args.get('dining_hall_id')
    if dining_hall_id:
        threading.Thread(target=scrape_dining_hall, args=(dining_hall_id, date), daemon=False).start()
    else:
        threading.Thread(target=scrape_all_dining_halls, args=(date,), daemon=False).start()
    return jsonify({'success': True, 'date': date, 'status': 'scrape started'})

@app.post('/api/scrape-week')
@_require_admin
def scrape_week():
    threading.Thread(target=scrape_full_week, daemon=False).start()
    return jsonify({'success': True, 'status': 'scrape started'})

def _run_embed_missing():
    from embeddings import generate_and_store_embedding
    import time
    cursor = db.foods.find({'embedding': {'$exists': False}}, {'_id': 0})
    for food in cursor:
        try:
            generate_and_store_embedding(db, food['rec_num'], food)
            time.sleep(0.1)
        except Exception as e:
            print(f"Embedding failed for {food['rec_num']}: {e}")

@app.post('/api/embed-missing')
@_require_admin
def embed_missing():
    threading.Thread(target=_run_embed_missing, daemon=False).start()
    return jsonify({'success': True, 'status': 'embedding started in background'})

@app.post('/api/cuisine-embeddings/generate')
@_require_admin
def generate_cuisine_embeddings():
    """One-time: generate and store embedding centroids for each cuisine category."""
    from embeddings import generate_embedding, compute_centroid
    import time

    CUISINES = {
        'comfort': ['Cheeseburger', 'Mac and Cheese', 'Grilled Cheese Sandwich', 'French Fries', 'Chicken Tenders'],
        'asian': ['Teriyaki Chicken', 'Vegetable Stir Fry', 'Fried Rice', 'Lo Mein Noodles', 'Orange Chicken'],
        'mexican': ['Chicken Burrito', 'Beef Tacos', 'Cheese Quesadilla', 'Spanish Rice and Beans', 'Nachos'],
        'italian': ['Spaghetti Marinara', 'Cheese Pizza', 'Caesar Salad', 'Chicken Parmesan', 'Penne Alfredo'],
        'indian': ['Chicken Tikka Masala', 'Butter Chicken Curry', 'Vegetable Biryani', 'Naan Bread', 'Chana Masala'],
        'southern': ['Fried Chicken', 'Cornbread', 'Collard Greens', 'Mashed Potatoes and Gravy', 'BBQ Pulled Pork'],
        'breakfast': ['Pancakes with Syrup', 'Scrambled Eggs and Bacon', 'French Toast', 'Breakfast Burrito', 'Waffles'],
    }

    results = {}
    for cuisine, foods in CUISINES.items():
        embeddings = []
        for food_name in foods:
            try:
                emb = generate_embedding(food_name)
                embeddings.append(emb)
                time.sleep(0.1)
            except Exception as e:
                print(f"Failed to embed {food_name}: {e}")

        if embeddings:
            centroid = compute_centroid(embeddings)
            db.cuisine_embeddings.update_one(
                {'cuisine': cuisine},
                {'$set': {'cuisine': cuisine, 'embedding': centroid}},
                upsert=True
            )
            results[cuisine] = len(embeddings)

    return jsonify({'success': True, 'generated': results})


# --- Auth ---

@app.post('/api/auth/guest')
@limiter.limit("10 per minute")
def auth_guest():
    try:
        import uuid
        guest_id = f"guest_{uuid.uuid4().hex}"

        db.users.insert_one({
            'user_id': guest_id,
            'is_guest': True,
            'created_at': datetime.now().isoformat()
        })

        token = pyjwt.encode(
            {'sub': guest_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
            os.environ['SECRET_KEY'],
            algorithm='HS256'
        )

        return jsonify({'success': True, 'user_id': guest_id, 'token': token})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/auth/apple')
@limiter.limit("10 per minute")
def auth_apple():
    try:
        data = request.get_json()
        apple_user_id = _ensure_string(data.get('apple_user_id', ''), 'apple_user_id')
        if not apple_user_id:
            return jsonify({'success': False, 'error': 'apple_user_id required'}), 400

        db.users.update_one(
            {'apple_user_id': apple_user_id},
            {'$setOnInsert': {'apple_user_id': apple_user_id, 'created_at': datetime.now().isoformat()}},
            upsert=True
        )

        token = pyjwt.encode(
            {'sub': apple_user_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
            os.environ['SECRET_KEY'],
            algorithm='HS256'
        )

        return jsonify({'success': True, 'user_id': apple_user_id, 'token': token})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/auth/upgrade')
@require_auth
@limiter.limit("10 per minute")
def upgrade_guest():
    """Upgrade a guest account to an Apple account, migrating all data."""
    try:
        data = request.get_json()
        apple_user_id = _ensure_string(data.get('apple_user_id', ''), 'apple_user_id')
        if not apple_user_id:
            return jsonify({'success': False, 'error': 'apple_user_id required'}), 400

        guest_id = g.user_id
        if not guest_id.startswith('guest_'):
            return jsonify({'success': False, 'error': 'not a guest account'}), 400

        # Create or find the Apple user
        db.users.update_one(
            {'apple_user_id': apple_user_id},
            {'$setOnInsert': {'apple_user_id': apple_user_id, 'created_at': datetime.now().isoformat()}},
            upsert=True
        )

        # Migrate favorites, station_favorites, preferences, and intake from guest to Apple user
        db.favorites.update_many({'user_id': guest_id}, {'$set': {'user_id': apple_user_id}})
        db.station_favorites.update_many({'user_id': guest_id}, {'$set': {'user_id': apple_user_id}})
        db.preferences.update_many({'user_id': guest_id}, {'$set': {'user_id': apple_user_id}})
        db.intake.update_many({'user_id': guest_id}, {'$set': {'user_id': apple_user_id}})

        # Delete the guest user record
        db.users.delete_one({'user_id': guest_id})

        token = pyjwt.encode(
            {'sub': apple_user_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
            os.environ['SECRET_KEY'],
            algorithm='HS256'
        )

        return jsonify({'success': True, 'user_id': apple_user_id, 'token': token})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/auth/refresh')
@require_auth
@limiter.limit("10 per minute")
def refresh_token():
    try:
        token = pyjwt.encode(
            {'sub': g.user_id, 'exp': datetime.now(timezone.utc) + timedelta(days=90)},
            os.environ['SECRET_KEY'],
            algorithm='HS256'
        )
        return jsonify({'success': True, 'token': token})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# --- Favorites (auth required) ---

@app.get('/api/favorites')
@require_auth
def get_favorites():
    try:
        favs = list(db.favorites.find({'user_id': g.user_id}, {'_id': 0}))
        return jsonify({'success': True, 'data': favs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/favorites')
@require_auth
def add_favorite():
    try:
        data = request.get_json()
        rec_num = _ensure_string(data.get('rec_num', ''), 'rec_num')
        name = _ensure_string(data.get('name', ''), 'name')
        if not rec_num:
            return jsonify({'success': False, 'error': 'rec_num required'}), 400

        db.favorites.update_one(
            {'user_id': g.user_id, 'rec_num': rec_num},
            {'$set': {'user_id': g.user_id, 'rec_num': rec_num, 'name': name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.delete('/api/favorites')
@require_auth
def remove_favorite():
    try:
        data = request.get_json()
        rec_num = _ensure_string(data.get('rec_num', ''), 'rec_num')
        if not rec_num:
            return jsonify({'success': False, 'error': 'rec_num required'}), 400

        db.favorites.delete_one({'user_id': g.user_id, 'rec_num': rec_num})
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# --- Station Favorites (auth required) ---

@app.get('/api/station-favorites')
@require_auth
def get_station_favorites():
    try:
        favs = list(db.station_favorites.find({'user_id': g.user_id}, {'_id': 0}))
        return jsonify({'success': True, 'data': favs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/station-favorites')
@require_auth
def add_station_favorite():
    try:
        data = request.get_json()
        station_name = _ensure_string(data.get('station_name', ''), 'station_name')
        if not station_name:
            return jsonify({'success': False, 'error': 'station_name required'}), 400

        db.station_favorites.update_one(
            {'user_id': g.user_id, 'station_name': station_name},
            {'$set': {'user_id': g.user_id, 'station_name': station_name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.delete('/api/station-favorites')
@require_auth
def remove_station_favorite():
    try:
        data = request.get_json()
        station_name = _ensure_string(data.get('station_name', ''), 'station_name')
        if not station_name:
            return jsonify({'success': False, 'error': 'station_name required'}), 400

        db.station_favorites.delete_one({'user_id': g.user_id, 'station_name': station_name})
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# --- Preferences (auth required) ---

@app.get('/api/preferences')
@require_auth
def get_preferences():
    try:
        prefs = db.preferences.find_one({'user_id': g.user_id}, {'_id': 0})
        if not prefs:
            prefs = {'user_id': g.user_id, 'vegetarian': False, 'vegan': False, 'allergens': [], 'cuisine_prefs': []}
        return jsonify({'success': True, 'data': prefs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.put('/api/preferences')
@require_auth
def update_preferences():
    try:
        data = request.get_json()
        vegetarian = data.get('vegetarian', False)
        vegan = data.get('vegan', False)
        allergens = data.get('allergens', [])
        cuisine_prefs = data.get('cuisine_prefs', [])

        # Validate types to prevent operator injection
        if not isinstance(vegetarian, bool) or not isinstance(vegan, bool):
            return jsonify({'success': False, 'error': 'vegetarian and vegan must be booleans'}), 400
        if not isinstance(allergens, list) or not all(isinstance(a, str) for a in allergens):
            return jsonify({'success': False, 'error': 'allergens must be a list of strings'}), 400
        if not isinstance(cuisine_prefs, list) or not all(isinstance(c, str) for c in cuisine_prefs):
            return jsonify({'success': False, 'error': 'cuisine_prefs must be a list of strings'}), 400

        db.preferences.update_one(
            {'user_id': g.user_id},
            {'$set': {
                'user_id': g.user_id,
                'vegetarian': vegetarian,
                'vegan': vegan,
                'allergens': allergens,
                'cuisine_prefs': cuisine_prefs,
            }},
            upsert=True
        )
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# --- Intake Tracking (auth required) ---

@app.get('/api/intake')
@require_auth
def get_intake():
    try:
        query = {'user_id': g.user_id}
        date = request.args.get('date')
        if date:
            query['date'] = date
        items = list(db.intake.find(query, {'_id': 0}))
        return jsonify({'success': True, 'data': items})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/intake')
@require_auth
def log_intake():
    try:
        data = request.get_json()
        rec_num = _ensure_string(data.get('rec_num', ''), 'rec_num')
        name = _ensure_string(data.get('name', ''), 'name')
        date = _ensure_string(data.get('date', ''), 'date')
        meal_period = _ensure_string(data.get('meal_period', ''), 'meal_period')

        if not rec_num:
            return jsonify({'success': False, 'error': 'rec_num required'}), 400

        calories = data.get('calories', 0)
        protein_g = data.get('protein_g', 0.0)
        carbs_g = data.get('carbs_g', 0.0)
        fat_g = data.get('fat_g', 0.0)

        if not isinstance(calories, (int, float)):
            return jsonify({'success': False, 'error': 'calories must be a number'}), 400
        if not all(isinstance(v, (int, float)) for v in [protein_g, carbs_g, fat_g]):
            return jsonify({'success': False, 'error': 'macros must be numbers'}), 400

        db.intake.insert_one({
            'user_id': g.user_id,
            'rec_num': rec_num,
            'name': name,
            'date': date,
            'meal_period': meal_period,
            'calories': int(calories),
            'protein_g': float(protein_g),
            'carbs_g': float(carbs_g),
            'fat_g': float(fat_g),
            'logged_at': datetime.now().isoformat(),
        })
        return jsonify({'success': True})
    except ValueError as e:
        return jsonify({'success': False, 'error': str(e)}), 400
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.delete('/api/intake')
@require_auth
def remove_intake():
    try:
        data = request.get_json()
        rec_num = _ensure_string(data.get('rec_num', ''), 'rec_num')
        date = _ensure_string(data.get('date', ''), 'date')
        logged_at = _ensure_string(data.get('logged_at', ''), 'logged_at')

        if not rec_num:
            return jsonify({'success': False, 'error': 'rec_num required'}), 400

        query = {'user_id': g.user_id, 'rec_num': rec_num}
        if date:
            query['date'] = date
        if logged_at:
            query['logged_at'] = logged_at

        db.intake.delete_one(query)
        return jsonify({'success': True})
    except ValueError as e:
        return jsonify({'success': False, 'error': str(e)}), 400
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
