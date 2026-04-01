# Uses requests (already in requirements.txt) — no openai SDK needed.
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


def generate_and_store_embedding(db, rec_num: str, food_doc: dict) -> None:
    """No-op if embedding already exists (idempotent). Otherwise generates and persists it."""
    if food_doc.get("embedding"):
        return
    embedding = generate_embedding(build_embedding_text(food_doc))
    db.foods.update_one({"rec_num": rec_num}, {"$set": {"embedding": embedding}})


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
