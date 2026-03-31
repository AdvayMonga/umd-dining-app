"""
ranker.py — Feed ranking and recommendation logic.

All scoring is pure logic: no DB access. The caller (routes.py) fetches
all required data and passes it in. This keeps the ranker easy to test
and easy to extend with AI/ML signals later.

Scoring is additive — multiple signals can fire for the same item.
Tag is assigned based on the highest-priority signal that fired.
"""

import random
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
):
    """
    Score, tag, and sort menu items for the feed.

    Args:
        menu_entries:     list of dicts from db.menus
        foods:            dict mapping rec_num -> food doc from db.foods
        fav_rec_nums:     set of rec_nums the user has favorited
        fav_stations:     set of station names the user has favorited
        user_prefs:       dict with keys 'vegetarian' (bool), 'vegan' (bool)
        popular_rec_nums: set of rec_nums trending across all users
        date_seed:        string used to seed the shuffle of untagged items

    Returns:
        list of item dicts with 'tag' field, ordered:
          - scored items (score > 0) descending by score
          - untagged entrees (score == 0) shuffled deterministically
          - sides with no tag are excluded entirely
    """
    is_vegetarian = user_prefs.get('vegetarian', False)
    is_vegan = user_prefs.get('vegan', False)
    fav_centroid = compute_centroid(fav_embeddings) if fav_embeddings else None

    scored = []    # (score, tag, item_dict)
    untagged = []  # item_dicts with score == 0

    for entry in menu_entries:
        food = foods.get(entry['rec_num'], {})
        nutrition = food.get('nutrition') or {}
        station = entry.get('station', '')
        rec_num = entry['rec_num']
        dietary_icons = entry.get('dietary_icons', [])
        is_side = 'side' in station.lower()

        # --- Compute additive score ---
        score = 0
        signals = set()

        if rec_num in fav_rec_nums:
            score += 100
            signals.add('favorite')

        if station in fav_stations:
            score += 60
            signals.add('favorite_station')

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

        if not is_side:
            protein = get_protein(nutrition)
            calories = get_calories(nutrition)

            if protein is not None and protein >= 20:
                score += 20
                signals.add('high_protein')

            if (protein is not None and protein >= 5
                    and calories is not None and calories > 0
                    and (protein * 4) / calories >= 0.25):
                score += 15
                signals.add('protein_ratio')

            if fav_centroid is not None:
                item_embedding = food.get('embedding')
                if item_embedding and cosine_similarity(fav_centroid, item_embedding) >= 0.82:
                    score += 25
                    signals.add('similar_to_favorites')

        # Drop untagged sides
        if is_side and score == 0:
            continue

        # --- Assign display tag (highest-priority signal) ---
        if 'favorite' in signals:
            tag = 'Favorite'
        elif 'trending' in signals:
            tag = 'Trending'
        elif 'similar_to_favorites' in signals:
            tag = 'Recommended'
        elif 'high_protein' in signals or 'protein_ratio' in signals:
            tag = 'High Protein'
        else:
            tag = None

        item = {
            'name': food.get('name', ''),
            'rec_num': rec_num,
            'dining_hall_id': entry['dining_hall_id'],
            'date': entry['date'],
            'meal_period': entry.get('meal_period', 'Unknown'),
            'station': station or 'Unknown',
            'dietary_icons': dietary_icons,
            'nutrition_fetched': food.get('nutrition_fetched', False),
            'nutrition': food.get('nutrition', {}),
            'allergens': food.get('allergens', ''),
            'ingredients': food.get('ingredients', ''),
            'tag': tag,
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
