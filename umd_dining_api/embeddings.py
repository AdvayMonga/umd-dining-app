# Uses requests (already in requirements.txt) — no openai SDK needed.
import os
import math
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


def generate_and_store_embedding(db, rec_num: str, food_doc: dict) -> None:
    """No-op if embedding already exists (idempotent). Otherwise generates and persists it."""
    if food_doc.get("embedding"):
        return
    embedding = generate_embedding(build_embedding_text(food_doc))
    db.foods.update_one({"rec_num": rec_num}, {"$set": {"embedding": embedding}})


def cosine_similarity(vec_a: list, vec_b: list) -> float:
    """Cosine similarity in [-1, 1]. Returns 0.0 if either vector is zero-magnitude."""
    dot = sum(a * b for a, b in zip(vec_a, vec_b))
    mag_a = math.sqrt(sum(a * a for a in vec_a))
    mag_b = math.sqrt(sum(b * b for b in vec_b))
    return 0.0 if mag_a == 0.0 or mag_b == 0.0 else dot / (mag_a * mag_b)


def compute_centroid(embeddings: list):
    """Mean vector of a list of embeddings. Returns None if list is empty."""
    if not embeddings:
        return None
    n = len(embeddings)
    dim = len(embeddings[0])
    centroid = [0.0] * dim
    for vec in embeddings:
        for i, val in enumerate(vec):
            centroid[i] += val
    return [x / n for x in centroid]
