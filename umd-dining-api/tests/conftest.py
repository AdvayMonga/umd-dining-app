"""Shared test setup.

The API modules read config at import time (main.py requires MONGO_URI and
builds a Motor client), so env vars are set before any import. Motor connects
lazily, so a fake URI never opens a socket — no test touches a real database.
"""
import os
import sys
from pathlib import Path

API_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(API_ROOT))
# NB: lambda/ is deliberately NOT on sys.path — it holds its own embeddings.py
# and scraper_core.py that would shadow the API modules of the same name.
# test_scraper_icons.py loads those by file path instead.

os.environ.setdefault("MONGO_URI", "mongodb://localhost:27017/umd_dining_test")
os.environ.setdefault("SECRET_KEY", "test-secret-key-not-a-real-one")
os.environ.setdefault("ADMIN_SECRET", "test-admin-secret")

import pytest

# main.py imports routes at the bottom, and routes imports back from main, so
# `import routes` first hits a partially-initialized module. Importing main
# here resolves the cycle once for the whole suite.
import main  # noqa: F401,E402


class FakeCursor:
    """Stands in for a Motor cursor: supports .sort(...).limit(...).to_list(n)."""

    def __init__(self, docs):
        self._docs = list(docs)

    def sort(self, *args, **kwargs):
        return self

    def limit(self, n):
        self._docs = self._docs[:n]
        return self

    async def to_list(self, length=None):
        return list(self._docs) if length is None else list(self._docs[:length])


class FakeCollection:
    """In-memory collection supporting the query subset the code actually uses."""

    def __init__(self, docs=None):
        self.docs = list(docs or [])
        self.updates = []

    @staticmethod
    def _matches(doc, query):
        for key, cond in query.items():
            if key == "$or":
                if not any(FakeCollection._matches(doc, sub) for sub in cond):
                    return False
            elif isinstance(cond, dict) and "$in" in cond:
                if doc.get(key) not in cond["$in"]:
                    return False
            elif doc.get(key) != cond:
                return False
        return True

    def find(self, query=None, projection=None):
        return FakeCursor([d for d in self.docs if self._matches(d, query or {})])

    async def find_one(self, query=None, projection=None):
        for d in self.docs:
            if self._matches(d, query or {}):
                return d
        return None

    async def update_one(self, query, update, upsert=False):
        self.updates.append((query, update, upsert))
        existing = await self.find_one(query)
        if existing is None and upsert:
            self.docs.append(dict(update.get("$setOnInsert", update.get("$set", {}))))
        return None

    async def distinct(self, field, query=None):
        return sorted({d.get(field) for d in self.docs
                       if self._matches(d, query or {}) and d.get(field) is not None})


class FakeDB:
    """Attribute access mints collections on demand, like a Motor database."""

    def __init__(self, **collections):
        self._collections = {name: FakeCollection(docs) for name, docs in collections.items()}

    def __getattr__(self, name):
        return self._collections.setdefault(name, FakeCollection())


@pytest.fixture
def fake_db():
    return FakeDB
