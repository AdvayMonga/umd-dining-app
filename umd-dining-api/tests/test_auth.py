"""JWT handling and the guest account lifecycle.

Guest docs TTL-expire 7 days after creation while tokens live 90 days, so
get_current_user re-creates a missing guest — except when the id was
tombstoned by account deletion or an Apple upgrade, where deletion must
remain a real revocation.
"""
import pytest
from fastapi import HTTPException

import routes
from conftest import FakeDB


async def call_current_user(token):
    return await routes.get_current_user(authorization=f"Bearer {token}")


class TestTokens:
    def test_round_trip_preserves_subject(self):
        import jwt as pyjwt
        token = routes._make_token("guest_abc")
        payload = pyjwt.decode(token, routes.SECRET_KEY, algorithms=["HS256"])
        assert payload["sub"] == "guest_abc"

    def test_token_carries_an_expiry(self):
        import jwt as pyjwt
        payload = pyjwt.decode(routes._make_token("u1"), routes.SECRET_KEY, algorithms=["HS256"])
        assert "exp" in payload


class TestGetCurrentUser:
    async def test_existing_user_is_accepted(self, monkeypatch):
        monkeypatch.setattr(routes, "db", FakeDB(users=[{"user_id": "u1"}]))
        assert await call_current_user(routes._make_token("u1")) == "u1"

    async def test_apple_user_matched_by_apple_user_id(self, monkeypatch):
        monkeypatch.setattr(routes, "db", FakeDB(users=[{"apple_user_id": "apple.1"}]))
        assert await call_current_user(routes._make_token("apple.1")) == "apple.1"

    async def test_missing_guest_account_is_recreated(self, monkeypatch):
        db = FakeDB(users=[], revoked_users=[])
        monkeypatch.setattr(routes, "db", db)
        assert await call_current_user(routes._make_token("guest_x")) == "guest_x"
        assert db.users.updates, "expected the guest account to be re-created"

    async def test_revoked_guest_is_not_resurrected(self, monkeypatch):
        # deleting an account must stay a revocation for the token's full life
        db = FakeDB(users=[], revoked_users=[{"user_id": "guest_gone"}])
        monkeypatch.setattr(routes, "db", db)
        with pytest.raises(HTTPException) as exc:
            await call_current_user(routes._make_token("guest_gone"))
        assert exc.value.status_code == 401
        assert not db.users.updates

    async def test_missing_non_guest_account_is_rejected(self, monkeypatch):
        monkeypatch.setattr(routes, "db", FakeDB(users=[], revoked_users=[]))
        with pytest.raises(HTTPException) as exc:
            await call_current_user(routes._make_token("apple.deleted"))
        assert exc.value.status_code == 401

    async def test_missing_authorization_header_is_rejected(self, monkeypatch):
        monkeypatch.setattr(routes, "db", FakeDB(users=[]))
        with pytest.raises(HTTPException) as exc:
            await routes.get_current_user(authorization="")
        assert exc.value.status_code == 401

    async def test_garbage_token_is_rejected(self, monkeypatch):
        monkeypatch.setattr(routes, "db", FakeDB(users=[]))
        with pytest.raises(HTTPException) as exc:
            await call_current_user("not-a-jwt")
        assert exc.value.status_code == 401

    async def test_token_without_subject_is_rejected_not_a_500(self, monkeypatch):
        import jwt as pyjwt
        monkeypatch.setattr(routes, "db", FakeDB(users=[]))
        token = pyjwt.encode({"foo": "bar"}, routes.SECRET_KEY, algorithm="HS256")
        with pytest.raises(HTTPException) as exc:
            await call_current_user(token)
        assert exc.value.status_code == 401

    async def test_expired_token_is_rejected(self, monkeypatch):
        import jwt as pyjwt
        from datetime import datetime, timedelta, timezone
        monkeypatch.setattr(routes, "db", FakeDB(users=[{"user_id": "u1"}]))
        expired = pyjwt.encode(
            {"sub": "u1", "exp": datetime.now(timezone.utc) - timedelta(days=1)},
            routes.SECRET_KEY, algorithm="HS256")
        with pytest.raises(HTTPException) as exc:
            await call_current_user(expired)
        assert exc.value.status_code == 401


class TestGetOptionalUser:
    async def test_returns_none_without_a_header(self):
        assert await routes.get_optional_user(authorization="") is None

    async def test_returns_none_for_an_invalid_token(self):
        assert await routes.get_optional_user(authorization="Bearer nonsense") is None

    async def test_returns_none_when_subject_missing(self):
        import jwt as pyjwt
        token = pyjwt.encode({"foo": "bar"}, routes.SECRET_KEY, algorithm="HS256")
        assert await routes.get_optional_user(authorization=f"Bearer {token}") is None

    async def test_returns_subject_for_a_valid_token(self):
        token = routes._make_token("guest_ok")
        assert await routes.get_optional_user(authorization=f"Bearer {token}") == "guest_ok"


class TestAdminAuth:
    async def test_correct_key_is_accepted(self):
        await routes.require_admin(x_admin_key=routes.ADMIN_SECRET)

    async def test_wrong_key_is_rejected(self):
        with pytest.raises(HTTPException) as exc:
            await routes.require_admin(x_admin_key="wrong")
        assert exc.value.status_code == 403

    async def test_non_ascii_key_is_rejected_not_a_500(self):
        # str compare_digest raises TypeError on non-ASCII; headers decode as latin-1
        with pytest.raises(HTTPException) as exc:
            await routes.require_admin(x_admin_key="Ã¿-not-ascii")
        assert exc.value.status_code == 403
