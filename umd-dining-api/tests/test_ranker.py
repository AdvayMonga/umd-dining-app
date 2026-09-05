"""Feed ranking: nutrition parsing, item filters, scoring, dedup, ordering."""
import pytest

import ranker
from ranker import (
    _count_top_level_ingredients,
    _is_condiment,
    _is_single_ingredient,
    get_calories,
    get_protein,
    rank_items,
)

# frequency 4-5 is the neutral band: no "rotating special" boost (<=3) and no
# staple/frequent penalty (>=6). Entries default to frequency 1, which scores.
NEUTRAL_FREQ = 4


def entry(rec_num, **over):
    base = {
        "rec_num": rec_num,
        "dining_hall_id": "19",
        "date": "9/5/2026",
        "meal_period": "Lunch",
        "station": "Grill",
        "dietary_icons": [],
        "frequency": NEUTRAL_FREQ,
    }
    base.update(over)
    return base


def food(rec_num, **over):
    base = {
        "rec_num": rec_num,
        "name": f"Food {rec_num}",
        "ingredients": "chicken, rice, broccoli, sauce",
        "nutrition": {"Calories": "400", "Protein": "10g", "Total Carbohydrate": "45g", "Total Fat": "15g"},
    }
    base.update(over)
    return base


def rank(entries, foods=None, **over):
    kwargs = {
        "menu_entries": entries,
        "foods": foods if foods is not None else {e["rec_num"]: food(e["rec_num"]) for e in entries},
        "fav_rec_nums": set(),
        "fav_stations": set(),
        "user_prefs": {},
        "popular_rec_nums": set(),
        "date_seed": "9/5/2026",
    }
    kwargs.update(over)
    return rank_items(**kwargs)


class TestNutritionParsing:
    @pytest.mark.parametrize("value,expected", [
        ("32g", 32.0), ("450", 450.0), ("12.5g", 12.5), ("", None), (None, None),
    ])
    def test_parse_number(self, value, expected):
        assert ranker._parse_number(value) == expected

    def test_protein_key_variants(self):
        assert get_protein({"Protein": "25g"}) == 25.0
        assert get_protein({"Total Protein": "18g"}) == 18.0
        assert get_protein({}) is None

    def test_calories_key_variants(self):
        assert get_calories({"Calories": "310"}) == 310.0
        assert get_calories({"Energy": "290"}) == 290.0


class TestIngredientHeuristics:
    def test_sub_ingredients_in_parens_are_not_counted(self):
        assert _count_top_level_ingredients("chicken, sauce (water, salt, sugar), rice") == 3

    def test_single_ingredient_detection(self):
        assert _is_single_ingredient({"ingredients": "Banana"})
        assert _is_single_ingredient({"ingredients": ""})
        assert not _is_single_ingredient({"ingredients": "flour, water, yeast"})

    def test_condiment_is_low_calorie_and_few_ingredients(self):
        assert _is_condiment({"nutrition": {"Calories": "35"}, "ingredients": "water, salt"})
        # plenty of calories -> a real dish, not a condiment
        assert not _is_condiment({"nutrition": {"Calories": "400"}, "ingredients": "water, salt"})
        # unknown calories must not be guessed as a condiment
        assert not _is_condiment({"nutrition": {}, "ingredients": "water, salt"})


class TestScoringAndTags:
    def test_favorite_is_tagged_and_outranks_neutral_item(self):
        result = rank([entry("A"), entry("B")], fav_rec_nums={"A"})
        assert result[0]["rec_num"] == "A"
        assert "Favorite" in result[0]["tags"]
        assert result[0]["tag"] == "Favorite"

    def test_trending_tag(self):
        result = rank([entry("A")], popular_rec_nums={"A"})
        assert "Trending" in result[0]["tags"]

    def test_high_protein_tag(self):
        foods = {"A": food("A", nutrition={"Calories": "500", "Protein": "30g"})}
        result = rank([entry("A")], foods=foods)
        assert "High Protein" in result[0]["tags"]

    def test_preferred_hall_outranks_other_hall(self):
        entries = [entry("A", dining_hall_id="19"), entry("B", dining_hall_id="51")]
        result = rank(entries, preferred_halls=["51"])
        assert result[0]["rec_num"] == "B"

    def test_similar_to_favorites_earns_recommended_tag(self):
        vec = [1.0, 0.0, 0.0]
        foods = {"A": food("A", embedding=vec)}
        result = rank([entry("A")], foods=foods, fav_embeddings=[vec])
        assert "Recommended" in result[0]["tags"]

    def test_favorite_suppresses_recommended_tag(self):
        vec = [1.0, 0.0, 0.0]
        foods = {"A": food("A", embedding=vec)}
        result = rank([entry("A")], foods=foods, fav_embeddings=[vec], fav_rec_nums={"A"})
        assert "Recommended" not in result[0]["tags"]

    def test_rotating_special_outranks_daily_staple(self):
        entries = [entry("STAPLE", frequency=10), entry("SPECIAL", frequency=1)]
        result = rank(entries)
        assert result[0]["rec_num"] == "SPECIAL"

    def test_breakfast_staples_escape_the_frequency_penalty(self):
        entries = [entry("EGGS", frequency=10, meal_period="Breakfast"),
                   entry("LUNCH_STAPLE", frequency=10, meal_period="Lunch")]
        result = rank(entries)
        assert [i["rec_num"] for i in result] == ["EGGS", "LUNCH_STAPLE"]


class TestFilters:
    def test_untagged_side_is_dropped(self):
        result = rank([entry("SIDE", station="Grill Sides"), entry("MAIN")])
        assert [i["rec_num"] for i in result] == ["MAIN"]

    def test_favorited_side_is_kept_and_station_name_merged(self):
        result = rank([entry("SIDE", station="Grill Sides")], fav_rec_nums={"SIDE"})
        assert len(result) == 1
        assert result[0]["station"] == "Grill"

    def test_untagged_single_ingredient_item_is_dropped(self):
        foods = {"BANANA": food("BANANA", ingredients="Banana"), "MAIN": food("MAIN")}
        result = rank([entry("BANANA"), entry("MAIN")], foods=foods)
        assert [i["rec_num"] for i in result] == ["MAIN"]

    def test_favorited_single_ingredient_item_survives(self):
        foods = {"BANANA": food("BANANA", ingredients="Banana")}
        result = rank([entry("BANANA")], foods=foods, fav_rec_nums={"BANANA"})
        assert len(result) == 1


class TestDedupAndCaps:
    def test_duplicate_rec_nums_appear_once(self):
        result = rank([entry("A"), entry("A", station="Deli")])
        assert len(result) == 1

    def test_caps_at_20_per_hall_and_meal_period(self):
        entries = [entry(f"R{i}") for i in range(25)]
        result = rank(entries)
        assert len(result) == 20

    def test_cap_is_per_hall_meal_combination(self):
        entries = ([entry(f"A{i}", dining_hall_id="19") for i in range(25)]
                   + [entry(f"B{i}", dining_hall_id="51") for i in range(25)])
        result = rank(entries)
        assert len(result) == 40

    def test_sixth_favorite_is_penalized_below_the_top_five(self):
        favs = {f"F{i}" for i in range(6)}
        entries = [entry(f"F{i}") for i in range(6)] + [entry("TRENDING")]
        result = rank(entries, fav_rec_nums=favs, popular_rec_nums={"TRENDING"})
        # 100 - 70 = 30 for the demoted favorite, below trending's 35
        assert result[-1]["rec_num"].startswith("F")
        assert "TRENDING" in [i["rec_num"] for i in result[:6]]


class TestDeterminism:
    def test_same_seed_gives_same_order(self):
        entries = [entry(f"R{i}") for i in range(10)]
        assert [i["rec_num"] for i in rank(entries)] == [i["rec_num"] for i in rank(entries)]

    def test_seed_is_stable_across_processes(self):
        # crc32, not hash(): hash() is randomized per process, which made the
        # "deterministic" daily shuffle differ across workers and restarts.
        import zlib
        assert zlib.crc32(b"9/5/2026") == zlib.crc32("9/5/2026".encode())


class TestEmptyInput:
    def test_no_entries_returns_empty(self):
        assert rank([]) == []
