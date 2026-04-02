"""
ranker.py — Feed ranking and recommendation logic.

All scoring is pure logic: no DB access. The caller (routes.py) fetches
all required data and passes it in. This keeps the ranker easy to test
and easy to extend with AI/ML signals later.

Scoring is additive — multiple signals can fire for the same item.
Tag is assigned based on the highest-priority signal that fired.
"""

import random
import re
from embeddings import cosine_similarity, compute_centroid


# ---------------------------------------------------------------------------
# Nutrition helpers
# ---------------------------------------------------------------------------

def _parse_number(value):
    """Extract the first number from a nutrition string like '32g' or '450'."""
    if not value:
        return None
    try:
        return float(''.join(c for c in str(value) if c.isdigit() or c == '.'))
    except Exception:
        return None


def _get_nutrient(nutrition, *keys):
    """Try multiple key variants and return the first numeric value found."""
    for key in keys:
        val = _parse_number(nutrition.get(key))
        if val is not None:
            return val
    return None


def get_protein(nutrition):
    return _get_nutrient(nutrition, 'Protein', 'Total Protein', 'protein')


def get_calories(nutrition):
    return _get_nutrient(nutrition, 'Calories', 'calories', 'Energy')


def get_carbs(nutrition):
    return _get_nutrient(nutrition, 'Total Carbohydrate', 'Carbohydrates', 'carbs')


def get_fat(nutrition):
    return _get_nutrient(nutrition, 'Total Fat', 'Fat', 'fat')


def _is_single_ingredient(food):
    """Check if a food item has 0 or 1 ingredients (e.g. 'Banana', 'Rice')."""
    ingredients = food.get('ingredients', '')
    if not ingredients:
        return True
    parts = [p.strip() for p in ingredients.split(',') if p.strip()]
    return len(parts) <= 1


# ---------------------------------------------------------------------------
# Core ranking function
# ---------------------------------------------------------------------------

def rank_items(
    menu_entries,
    foods,
    fav_rec_nums,
    fav_stations,
    user_prefs,
    popular_rec_nums,
    date_seed,
    fav_embeddings=None,
    user_views=None,
    global_views=None,
    hall_interest=None,
):
    """
    Score, tag, and sort menu items for the feed.

    Args:
        menu_entries:      list of dicts from db.menus
        foods:             dict mapping rec_num -> food doc from db.foods
        fav_rec_nums:      set of rec_nums the user has favorited
        fav_stations:      set of station names the user has favorited
        user_prefs:        dict with keys 'vegetarian' (bool), 'vegan' (bool)
        popular_rec_nums:  set of rec_nums trending across all users (by favorites)
        date_seed:         string used to seed the shuffle of untagged items
        fav_embeddings:    list of embedding vectors for user's favorites
        user_views:        dict mapping rec_num -> view count for this user
        global_views:      dict mapping rec_num -> view count across all users
        hall_interest:     dict mapping dining_hall_id -> recent engagement count

    Returns:
        list of item dicts with 'tag' field, ordered:
          - scored items (score > 0) descending by score
          - untagged entrees (score == 0) shuffled deterministically
          - sides with no tag are excluded entirely
          - single-ingredient items with no tag are excluded
    """
    is_vegetarian = user_prefs.get('vegetarian', False)
    is_vegan = user_prefs.get('vegan', False)
    fav_centroid = compute_centroid(fav_embeddings) if fav_embeddings else None
    user_views = user_views or {}
    global_views = global_views or {}
    hall_interest = hall_interest or {}

    # Compute max global views for normalization
    max_global_views = max(global_views.values()) if global_views else 1

    scored = []    # (score, tag, item_dict)
    untagged = []  # item_dicts with score == 0

    for entry in menu_entries:
        food = foods.get(entry['rec_num'], {})
        nutrition = food.get('nutrition') or {}
        station = entry.get('station', '')
        rec_num = entry['rec_num']
        dining_hall_id = entry.get('dining_hall_id', '')
        dietary_icons = entry.get('dietary_icons', [])
        is_side = 'side' in station.lower()
        # Merge sides with parent station for display (e.g. "Grill Sides" → "Grill")
        display_station = re.sub(r'\s+Sides?\s*$', '', station, flags=re.IGNORECASE) if is_side else station

        # --- Compute additive score ---
        score = 0
        signals = set()

        # Favorite: highest signal
        if rec_num in fav_rec_nums:
            score += 100
            signals.add('favorite')

        # Favorite station
        if station in fav_stations:
            score += 60
            signals.add('favorite_station')

        # Trending (favorited by many users)
        if rec_num in popular_rec_nums:
            score += 40
            signals.add('trending')

        # Dietary preference match
        if is_vegan and 'vegan' in dietary_icons:
            score += 20
            signals.add('pref_match')
        elif is_vegetarian and 'vegetarian' in dietary_icons:
            score += 20
            signals.add('pref_match')

        # --- Engagement signals ---

        # Personal re-engagement: user has viewed this item before
        personal_views = user_views.get(rec_num, 0)
        if personal_views >= 3:
            score += 15
            signals.add('personal_interest')
        elif personal_views >= 1:
            score += 8
            signals.add('personal_interest')

        # Global popularity by views (normalized, max +20)
        gv = global_views.get(rec_num, 0)
        if gv > 0:
            popularity_score = min(20, int(20 * (gv / max_global_views)))
            if popularity_score >= 5:
                score += popularity_score
                signals.add('popular_views')

        # Recent dining hall interest: boost items from halls user recently engaged with
        hall_engagement = hall_interest.get(dining_hall_id, 0)
        if hall_engagement >= 5:
            score += 15
            signals.add('hall_interest')
        elif hall_engagement >= 2:
            score += 8
            signals.add('hall_interest')

        # --- Nutrition & similarity signals (skip for sides) ---
        if not is_side:
            protein = get_protein(nutrition)
            carbs = get_carbs(nutrition)
            fat = get_fat(nutrition)

            if protein is not None and protein >= 15:
                score += 5
                signals.add('high_protein')

            macro_total = (protein or 0) + (carbs or 0) + (fat or 0)
            if (protein is not None and protein >= 5
                    and macro_total > 0
                    and protein / macro_total >= 0.25):
                score += 5
                signals.add('protein_ratio')

            # Tiered cosine similarity
            if fav_centroid is not None:
                item_embedding = food.get('embedding')
                if item_embedding:
                    sim = cosine_similarity(fav_centroid, item_embedding)
                    if sim >= 0.73:
                        score += 45
                        signals.add('similar_to_favorites')
                    elif sim >= 0.65:
                        score += 30
                        signals.add('similar_to_favorites')
                    elif sim >= 0.55:
                        score += 18
                        signals.add('somewhat_similar')

        # --- Filters ---

        # Drop untagged sides
        if is_side and score == 0:
            continue

        # Drop single-ingredient items unless they earned a score
        if _is_single_ingredient(food) and score == 0:
            continue

        # --- Assign display tags ---
        # Favorite, Trending, High Protein can all stack
        # Recommended is excluded if Favorite is present
        tags = []
        if 'favorite' in signals:
            tags.append('Favorite')
        if 'trending' in signals:
            tags.append('Trending')
        if ('similar_to_favorites' in signals or 'somewhat_similar' in signals) and 'favorite' not in signals:
            tags.append('Recommended')
        if 'high_protein' in signals or 'protein_ratio' in signals:
            tags.append('High Protein')

        tag = tags[0] if tags else None

        item = {
            'name': food.get('name', ''),
            'rec_num': rec_num,
            'dining_hall_id': entry['dining_hall_id'],
            'date': entry['date'],
            'meal_period': entry.get('meal_period', 'Unknown'),
            'station': display_station or 'Unknown',
            'dietary_icons': dietary_icons,
            'nutrition_fetched': food.get('nutrition_fetched', False),
            'nutrition': food.get('nutrition', {}),
            'allergens': food.get('allergens', ''),
            'ingredients': food.get('ingredients', ''),
            'tag': tag,
            'tags': tags,
        }

        if score > 0:
            scored.append((score, item))
        else:
            untagged.append(item)

    # Sort scored items descending; shuffle untagged with date-seeded RNG
    scored.sort(key=lambda x: -x[0])
    rng = random.Random(hash(date_seed))
    rng.shuffle(untagged)

    return [item for _, item in scored] + untagged
