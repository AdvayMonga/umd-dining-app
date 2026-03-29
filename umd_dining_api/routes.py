from flask import jsonify, request
from app import app, db
from datetime import datetime
import random
from scraper import scrape_all_dining_halls, scrape_dining_hall, scrape_full_week, fetch_and_cache_nutrition

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
        return jsonify({'success': False,'error': str(e)}), 500

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
def get_ranked_menu():
    try:
        date = request.args.get('date')
        dining_hall_ids = request.args.getlist('dining_hall_ids') or ['19', '51', '16']
        user_id = request.args.get('user_id')

        if not date:
            return jsonify({'success': False, 'error': 'date required'}), 400

        # Fetch menu entries for the date and halls
        menu_entries = list(db.menus.find(
            {'date': date, 'dining_hall_id': {'$in': dining_hall_ids}},
            {'_id': 0}
        ))

        # Join with foods collection
        rec_nums = [e['rec_num'] for e in menu_entries]
        foods = {f['rec_num']: f for f in db.foods.find({'rec_num': {'$in': rec_nums}}, {'_id': 0})}

        # Fetch user favorites and station favorites
        fav_rec_nums = set()
        fav_stations = set()
        if user_id:
            for fav in db.favorites.find({'user_id': user_id}, {'rec_num': 1, '_id': 0}):
                fav_rec_nums.add(fav['rec_num'])
            for sf in db.station_favorites.find({'user_id': user_id}, {'station_name': 1, '_id': 0}):
                fav_stations.add(sf['station_name'])

        def parse_number(value):
            try:
                return float(''.join(c for c in str(value) if c.isdigit() or c == '.'))
            except Exception:
                return None

        def get_protein(nutrition):
            for key in ['Protein', 'Total Protein', 'protein']:
                val = parse_number(nutrition.get(key))
                if val is not None:
                    return val
            return None

        def get_calories(nutrition):
            for key in ['Calories', 'calories', 'Energy']:
                val = parse_number(nutrition.get(key))
                if val is not None:
                    return val
            return None

        def score_item(entry, food):
            station = entry.get('station', '')
            is_side = 'side' in station.lower()
            rec_num = entry['rec_num']
            nutrition = food.get('nutrition') or {}

            if rec_num in fav_rec_nums:
                return 100, 'Favorite'
            if station in fav_stations:
                return 80, 'Favorite Station'
            if not is_side:
                protein = get_protein(nutrition)
                if protein is not None and protein >= 20:
                    return 50, 'High Protein'
                calories = get_calories(nutrition)
                if calories is not None and calories <= 400:
                    return 30, 'Low Calorie'
            if is_side:
                return -1, None  # hidden unless tagged above
            return 0, None  # untagged entree

        tagged_items = []
        untagged_items = []

        for entry in menu_entries:
            food = foods.get(entry['rec_num'], {})
            score, tag = score_item(entry, food)
            if score < 0:
                continue  # drop untagged sides

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
                'tag': tag,
            }

            if score > 0:
                tagged_items.append((score, item))
            else:
                untagged_items.append(item)

        # Sort tagged by score descending, shuffle untagged with date-seeded RNG
        tagged_items.sort(key=lambda x: -x[0])
        rng = random.Random(hash(date))
        rng.shuffle(untagged_items)

        result = [item for _, item in tagged_items] + untagged_items

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

        # Get menu entries
        menu_entries = list(db.menus.find(query, {'_id': 0}))

        # Join with foods collection
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

        return jsonify({
            'success': True,
            'count': len(items),
            'filters': query,
            'data': items
        })
    except Exception as e:
        return jsonify({'success': False,'error': str(e)}), 500

@app.get('/api/nutrition')
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
def search_menu():
    try:
        search_query = request.args.get('q', '')

        if not search_query:
            return jsonify({'success': False,'error': 'Search query required'}), 400

        # Search in foods collection by name
        foods = list(db.foods.find(
            {'name': {'$regex': search_query, '$options': 'i'}},
            {'_id': 0}
        ).limit(50))

        return jsonify({
            'success': True,
            'query': search_query,
            'count': len(foods),
            'data': foods
        })
    except Exception as e:
        return jsonify({'success': False,'error': str(e)}), 500

@app.post('/api/scrape')
def scrape():
    try:
        date = request.args.get('date', datetime.now().strftime('%-m/%-d/%Y'))
        dining_hall_id = request.args.get('dining_hall_id')
        if dining_hall_id:
            items = scrape_dining_hall(dining_hall_id, date)
        else:
            items = scrape_all_dining_halls(date)
        return jsonify({
            'success': True,
            'date': date,
            'items_scraped': len(items)
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/scrape-week')
def scrape_week():
    try:
        items = scrape_full_week()
        return jsonify({
            'success': True,
            'items_scraped': len(items)
        })
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# --- Station Favorites ---

@app.get('/api/station-favorites')
def get_station_favorites():
    try:
        user_id = request.args.get('user_id')
        if not user_id:
            return jsonify({'success': False, 'error': 'user_id required'}), 400
        favs = list(db.station_favorites.find({'user_id': user_id}, {'_id': 0}))
        return jsonify({'success': True, 'data': favs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/station-favorites')
def add_station_favorite():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        station_name = data.get('station_name')
        if not user_id or not station_name:
            return jsonify({'success': False, 'error': 'user_id and station_name required'}), 400
        db.station_favorites.update_one(
            {'user_id': user_id, 'station_name': station_name},
            {'$set': {'user_id': user_id, 'station_name': station_name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.delete('/api/station-favorites')
def remove_station_favorite():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        station_name = data.get('station_name')
        if not user_id or not station_name:
            return jsonify({'success': False, 'error': 'user_id and station_name required'}), 400
        db.station_favorites.delete_one({'user_id': user_id, 'station_name': station_name})
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# --- Auth & Favorites ---

@app.post('/api/auth/apple')
def auth_apple():
    try:
        data = request.get_json()
        apple_user_id = data.get('apple_user_id')
        if not apple_user_id:
            return jsonify({'success': False, 'error': 'apple_user_id required'}), 400

        db.users.update_one(
            {'apple_user_id': apple_user_id},
            {'$setOnInsert': {'apple_user_id': apple_user_id, 'created_at': datetime.now().isoformat()}},
            upsert=True
        )

        return jsonify({'success': True, 'user_id': apple_user_id})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.get('/api/favorites')
def get_favorites():
    try:
        user_id = request.args.get('user_id')
        if not user_id:
            return jsonify({'success': False, 'error': 'user_id required'}), 400

        favs = list(db.favorites.find({'user_id': user_id}, {'_id': 0}))
        return jsonify({'success': True, 'data': favs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.post('/api/favorites')
def add_favorite():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        rec_num = data.get('rec_num')
        name = data.get('name', '')

        if not user_id or not rec_num:
            return jsonify({'success': False, 'error': 'user_id and rec_num required'}), 400

        db.favorites.update_one(
            {'user_id': user_id, 'rec_num': rec_num},
            {'$set': {'user_id': user_id, 'rec_num': rec_num, 'name': name, 'added_at': datetime.now().isoformat()}},
            upsert=True
        )

        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.delete('/api/favorites')
def remove_favorite():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        rec_num = data.get('rec_num')

        if not user_id or not rec_num:
            return jsonify({'success': False, 'error': 'user_id and rec_num required'}), 400

        db.favorites.delete_one({'user_id': user_id, 'rec_num': rec_num})
        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

# --- User Preferences ---

@app.get('/api/preferences')
def get_preferences():
    try:
        user_id = request.args.get('user_id')
        if not user_id:
            return jsonify({'success': False, 'error': 'user_id required'}), 400

        prefs = db.preferences.find_one({'user_id': user_id}, {'_id': 0})
        if not prefs:
            prefs = {'user_id': user_id, 'vegetarian': False, 'vegan': False, 'allergens': []}

        return jsonify({'success': True, 'data': prefs})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@app.put('/api/preferences')
def update_preferences():
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        if not user_id:
            return jsonify({'success': False, 'error': 'user_id required'}), 400

        db.preferences.update_one(
            {'user_id': user_id},
            {'$set': {
                'user_id': user_id,
                'vegetarian': data.get('vegetarian', False),
                'vegan': data.get('vegan', False),
                'allergens': data.get('allergens', []),
            }},
            upsert=True
        )

        return jsonify({'success': True})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
