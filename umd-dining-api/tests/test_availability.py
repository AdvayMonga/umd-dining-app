"""Availability resolution: today first, then the next date inside the 7-day window."""

import routes
from conftest import FakeDB

TODAY = "9/5/2026"
HALLS = [{"hall_id": "19", "name": "Yahentamitsi Dining Hall"},
         {"hall_id": "51", "name": "251 North"}]


def menu(rec_num, date, hall="19", station="Grill"):
    return {"rec_num": rec_num, "date": date, "dining_hall_id": hall, "station": station}


async def resolve(rec_nums, menus, monkeypatch):
    monkeypatch.setattr(routes, "db", FakeDB(menus=menus, dining_halls=HALLS))
    return await routes._resolve_availability(rec_nums, today=TODAY)


class TestAvailableToday:
    async def test_item_on_todays_menu(self, monkeypatch):
        result = await resolve(["A"], [menu("A", TODAY)], monkeypatch)
        assert result["A"]["available_today"] is True
        assert result["A"]["station"] == "Grill"
        assert result["A"]["dining_hall_name"] == "Yahentamitsi Dining Hall"
        assert result["A"]["next_available_date"] is None
        assert result["A"]["unavailable_this_week"] is False

    async def test_today_wins_over_a_future_date(self, monkeypatch):
        menus = [menu("A", "9/8/2026", hall="51"), menu("A", TODAY, hall="19")]
        result = await resolve(["A"], menus, monkeypatch)
        assert result["A"]["available_today"] is True
        assert result["A"]["dining_hall_id"] == "19"


class TestUpcoming:
    async def test_next_date_within_the_week(self, monkeypatch):
        result = await resolve(["A"], [menu("A", "9/8/2026", hall="51")], monkeypatch)
        assert result["A"]["available_today"] is False
        assert result["A"]["next_available_date"] == "9/8/2026"
        assert result["A"]["dining_hall_name"] == "251 North"
        assert result["A"]["unavailable_this_week"] is False

    async def test_earliest_upcoming_date_wins(self, monkeypatch):
        menus = [menu("A", "9/10/2026"), menu("A", "9/7/2026")]
        result = await resolve(["A"], menus, monkeypatch)
        assert result["A"]["next_available_date"] == "9/7/2026"


class TestUnavailable:
    async def test_item_never_on_a_menu(self, monkeypatch):
        result = await resolve(["GHOST"], [], monkeypatch)
        assert result["GHOST"]["unavailable_this_week"] is True
        assert result["GHOST"]["available_today"] is False

    async def test_past_dates_do_not_count_as_upcoming(self, monkeypatch):
        result = await resolve(["A"], [menu("A", "9/1/2026")], monkeypatch)
        assert result["A"]["unavailable_this_week"] is True

    async def test_dates_beyond_the_window_are_not_scanned(self, monkeypatch):
        # the query is bounded to today+1..+7 so the menus collection can grow
        # without making this lookup slower
        result = await resolve(["A"], [menu("A", "10/20/2026")], monkeypatch)
        assert result["A"]["unavailable_this_week"] is True


class TestEdgeCases:
    async def test_empty_input_returns_empty(self, monkeypatch):
        assert await resolve([], [menu("A", TODAY)], monkeypatch) == {}

    async def test_every_requested_rec_num_is_present_in_the_result(self, monkeypatch):
        result = await resolve(["A", "B", "C"], [menu("A", TODAY)], monkeypatch)
        assert set(result) == {"A", "B", "C"}

    async def test_unparseable_stored_date_is_skipped(self, monkeypatch):
        result = await resolve(["A"], [menu("A", "not-a-date")], monkeypatch)
        assert result["A"]["unavailable_this_week"] is True
