# Uses requests (already in requirements.txt) — no openai SDK needed.
import asyncio
import os
import numpy as np
import requests

OPENAI_EMBEDDING_URL = "https://api.openai.com/v1/embeddings"
EMBEDDING_MODEL = "text-embedding-3-small"


def build_embedding_text(food_doc) -> str:
    parts = [f"{food_doc.get('name', '')}."]
    if food_doc.get('ingredients'):
        parts.append(f"Ingredients: {food_doc['ingredients']}.")
    if food_doc.get('allergens'):
        parts.append(f"Allergens: {food_doc['allergens']}.")
    return " ".join(parts)


def generate_embedding(text: str) -> list:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not set")
    response = requests.post(
        OPENAI_EMBEDDING_URL,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={"model": EMBEDDING_MODEL, "input": text},
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["data"][0]["embedding"]


async def generate_embedding_async(text: str) -> list:
    """Async wrapper — runs the sync OpenAI call in a thread executor."""
    return await asyncio.to_thread(generate_embedding, text)


def generate_and_store_embedding(db, rec_num: str, food_doc: dict) -> None:
    """No-op if embedding already exists (idempotent). Otherwise generates, persists, and computes similar foods."""
    if food_doc.get("embedding"):
        return
    embedding = generate_embedding(build_embedding_text(food_doc))
    db.foods.update_one({"rec_num": rec_num}, {"$set": {"embedding": embedding}})
    # Compute similar foods now that we have an embedding
    compute_and_store_similar(db, rec_num, embedding)


def compute_and_store_similar(db, rec_num: str, embedding: list, top_k: int = 5) -> None:
    """Compute top-5 similar foods by cosine similarity and store with scores."""
    target = np.asarray(embedding, dtype=np.float32)
    target_norm = np.linalg.norm(target)
    if target_norm == 0:
        return

    candidates = list(db.foods.find(
        {'rec_num': {'$ne': rec_num}, 'embedding': {'$exists': True}},
        {'rec_num': 1, 'embedding': 1, '_id': 0}
    ))
    if not candidates:
        return

    rec_nums_list = [c['rec_num'] for c in candidates]
    emb_matrix = np.asarray([c['embedding'] for c in candidates], dtype=np.float32)
    norms = np.linalg.norm(emb_matrix, axis=1)
    sims = np.dot(emb_matrix, target) / (norms * target_norm + 1e-10)

    top_indices = np.argsort(sims)[::-1][:top_k]
    similar = [{'rec_num': rec_nums_list[i], 'score': round(float(sims[i]), 4)}
               for i in top_indices]

    db.foods.update_one({'rec_num': rec_num}, {'$set': {'similar': similar}})


def backfill_all_similar(db, top_k: int = 5) -> int:
    """One-time job: load all embeddings once, compute similarities in-memory, write results."""
    # Single DB read — load everything into memory
    all_foods = list(db.foods.find(
        {'embedding': {'$exists': True}},
        {'rec_num': 1, 'embedding': 1, '_id': 0}
    ))
    if len(all_foods) < 2:
        return 0

    # Find which ones need similar computed
    needs_update = list(db.foods.find(
        {'embedding': {'$exists': True}, 'similar': {'$exists': False}},
        {'rec_num': 1, '_id': 0}
    ))
    needs_update_rns = {f['rec_num'] for f in needs_update}
    if not needs_update_rns:
        return 0

    # Build matrix once
    rec_nums = [f['rec_num'] for f in all_foods]
    emb_matrix = np.asarray([f['embedding'] for f in all_foods], dtype=np.float32)
    norms = np.linalg.norm(emb_matrix, axis=1)

    count = 0
    for i, rn in enumerate(rec_nums):
        if rn not in needs_update_rns:
            continue

        # Cosine similarity against all others (vectorized)
        sims = np.dot(emb_matrix, emb_matrix[i]) / (norms * norms[i] + 1e-10)
        sims[i] = -1  # exclude self

        top_indices = np.argsort(sims)[::-1][:top_k]
        similar = [{'rec_num': rec_nums[j], 'score': round(float(sims[j]), 4)}
                   for j in top_indices]

        db.foods.update_one({'rec_num': rn}, {'$set': {'similar': similar}})
        count += 1
        if count % 100 == 0:
            print(f"  Backfilled {count} / {len(needs_update_rns)}")

    return count


def cosine_similarity(vec_a, vec_b) -> float:
    """Cosine similarity in [-1, 1]. Returns 0.0 if either vector is zero-magnitude."""
    a, b = np.asarray(vec_a, dtype=np.float32), np.asarray(vec_b, dtype=np.float32)
    denom = np.linalg.norm(a) * np.linalg.norm(b)
    return 0.0 if denom == 0.0 else float(np.dot(a, b) / denom)


def compute_centroid(embeddings):
    """Mean vector of a list of embeddings. Returns None if list is empty."""
    if not embeddings:
        return None
    return np.mean(np.asarray(embeddings, dtype=np.float32), axis=0).tolist()
