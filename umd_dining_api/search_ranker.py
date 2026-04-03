"""
search_ranker.py — Search ranking and scoring logic.

All scoring is pure logic: no DB access. The caller (routes.py) fetches
all required data and passes it in. Same pattern as ranker.py.

Three-stage pipeline:
  1. Candidate retrieval (OR gate) — handled in routes.py
  2. Thresholding — filter garbage matches
  3. Ranking — additive scoring with text, semantic, and personalization signals
"""

import re
import numpy as np
from embeddings import cosine_similarity


# ---------------------------------------------------------------------------
# Text scoring
# ---------------------------------------------------------------------------

def compute_text_score(food_name: str, food_ingredients: str, query: str) -> float:
    """
    Score how well a food matches the query via text.
    Returns 0.0–1.0 (normalized).

    Scoring (raw, then normalized by /100):
      - Exact name match:          100
      - Name starts with query:     70
      - Name contains query (word): 50
      - Name contains query (sub):  30
      - Ingredient word match:      15
      - Ingredient substring match:  8
    """
    name_lower = food_name.lower()
    query_lower = query.lower()
    score = 0

    if name_lower == query_lower:
        score = 100
    elif name_lower.startswith(query_lower):
        score = 70
    elif re.search(r'\b' + re.escape(query_lower) + r'\b', name_lower):
        score = 50
    elif query_lower in name_lower:
        score = 30

    # Ingredient matching (additive, not replacing name score)
    ingredients_lower = food_ingredients.lower()
    if ingredients_lower:
        if re.search(r'\b' + re.escape(query_lower) + r'\b', ingredients_lower):
            score = max(score, 15)
            if score > 15:
                score += 5  # bonus for matching both name and ingredients
        elif query_lower in ingredients_lower:
            score = max(score, 8)

    return min(score / 100.0, 1.0)


# ---------------------------------------------------------------------------
# Thresholding (Stage 2)
# ---------------------------------------------------------------------------

TEXT_THRESHOLD = 0.05
SEMANTIC_THRESHOLD = 0.60

def passes_threshold(text_score: float, semantic_score: float, has_embedding: bool) -> bool:
    """
    A candidate passes if it has at least minimal relevance.
    Drop only if BOTH text and semantic are below their thresholds.
    Foods without embeddings get a pass on the semantic check.
    """
    if text_score >= TEXT_THRESHOLD:
        return True
    if has_embedding and semantic_score >= SEMANTIC_THRESHOLD:
        return True
    if not has_embedding and text_score > 0:
        return True
    return False


# ---------------------------------------------------------------------------
# Core ranking function (Stage 3)
# ---------------------------------------------------------------------------

def rank_search_results(
    candidates,
    query,
    query_embedding,
    fav_rec_nums=None,
    intake_counts=None,
    user_views=None,
    global_views=None,
):
    """
    Score and sort search candidates.

    Args:
        candidates:       list of food dicts (with 'embedding' key if available)
        query:            raw query string
        query_embedding:  embedding vector or None
        fav_rec_nums:     set of rec_nums the user has favorited
        intake_counts:    dict: rec_num -> intake count from tracker
        user_views:       dict: rec_num -> personal view count
        global_views:     dict: rec_num -> global view count

    Returns:
        list of food dicts, sorted by score descending, limited to 50.
    """
    fav_rec_nums = fav_rec_nums or set()
    intake_counts = intake_counts or {}
    user_views = user_views or {}
    global_views = global_views or {}

    max_global = max(global_views.values()) if global_views else 1

    scored = []

    for food in candidates:
        rec_num = food.get('rec_num', '')
        name = food.get('name', '')
        ingredients = food.get('ingredients', '')
        embedding = food.get('embedding')

        # --- Text relevance (max 100) ---
        text_score = compute_text_score(name, ingredients, query)
        text_points = text_score * 100

        # --- Semantic relevance (max 50) ---
        semantic_score = 0.0
        if query_embedding is not None and embedding is not None:
            semantic_score = cosine_similarity(query_embedding, embedding)
        semantic_points = max(0, semantic_score) * 50

        # --- Thresholding ---
        if not passes_threshold(text_score, semantic_score, embedding is not None):
            continue

        # --- Personalization signals ---
        personal_points = 0

        # Favorites
        if rec_num in fav_rec_nums:
            personal_points += 40

        # Tracker history
        intake = intake_counts.get(rec_num, 0)
        if intake >= 3:
            personal_points += 20
        elif intake >= 1:
            personal_points += 10

        # Personal views
        pv = user_views.get(rec_num, 0)
        if pv >= 3:
            personal_points += 15
        elif pv >= 1:
            personal_points += 8

        # Global popularity (max 12)
        gv = global_views.get(rec_num, 0)
        if gv > 0:
            pop = min(12, int(12 * (gv / max_global)))
            if pop >= 3:
                personal_points += pop

        total = text_points + semantic_points + personal_points

        # Build result item (strip embedding from output)
        item = {
            'rec_num': rec_num,
            'name': name,
            'nutrition': food.get('nutrition', {}),
            'nutrition_fetched': food.get('nutrition_fetched', False),
            'allergens': food.get('allergens', ''),
            'ingredients': ingredients,
        }
        scored.append((total, item))

    scored.sort(key=lambda x: -x[0])
    return [item for _, item in scored[:50]]
