"""Search relevance: text scoring tiers, thresholding, ranking, output shape."""

from search_ranker import compute_text_score, passes_threshold, rank_search_results


def candidate(rec_num, name=None, **over):
    base = {
        "rec_num": rec_num,
        "name": name or f"Food {rec_num}",
        "ingredients": "",
        "nutrition": {"Calories": "300"},
        "nutrition_fetched": True,
        "allergens": "",
    }
    base.update(over)
    return base


class TestTextScore:
    def test_tiers_are_ordered_exact_prefix_word_substring(self):
        exact = compute_text_score("chicken", "", "chicken")
        prefix = compute_text_score("chicken tikka", "", "chicken")
        word = compute_text_score("grilled chicken sandwich", "", "chicken")
        # "wrap" sits inside a word, so it is a substring hit, not a word hit
        substring = compute_text_score("Southwest chickenwrap", "", "wrap")
        assert exact > prefix > word > substring > 0

    def test_case_insensitive(self):
        assert compute_text_score("Chicken", "", "chicken") == compute_text_score("chicken", "", "Chicken")

    def test_no_match_scores_zero(self):
        assert compute_text_score("waffle", "syrup, butter", "chicken") == 0.0

    def test_ingredient_only_match_scores_low_but_nonzero(self):
        score = compute_text_score("Buddha Bowl", "quinoa, chicken, kale", "chicken")
        assert 0 < score < compute_text_score("chicken", "", "chicken")

    def test_score_never_exceeds_one(self):
        assert compute_text_score("chicken", "chicken, salt", "chicken") == 1.0


class TestThresholding:
    def test_strong_text_match_passes(self):
        assert passes_threshold(0.7, 0.0, has_embedding=True)

    def test_semantic_alone_passes_when_strong(self):
        assert passes_threshold(0.0, 0.8, has_embedding=True)

    def test_weak_on_both_is_dropped(self):
        assert not passes_threshold(0.0, 0.2, has_embedding=True)

    def test_without_embedding_any_text_signal_passes(self):
        assert passes_threshold(0.04, 0.0, has_embedding=False)

    def test_without_embedding_zero_text_is_dropped(self):
        assert not passes_threshold(0.0, 0.99, has_embedding=False)


class TestRanking:
    def test_better_text_match_ranks_first(self):
        results = rank_search_results(
            candidates=[candidate("B", "Chicken Caesar Wrap"), candidate("A", "Chicken")],
            query="chicken", query_embedding=None,
        )
        assert results[0]["rec_num"] == "A"

    def test_irrelevant_candidates_are_filtered_out(self):
        results = rank_search_results(
            candidates=[candidate("A", "Chicken"), candidate("Z", "Waffle")],
            query="chicken", query_embedding=None,
        )
        assert [r["rec_num"] for r in results] == ["A"]

    def test_favorites_boost_ranking(self):
        args = dict(candidates=[candidate("A", "Chicken Bowl"), candidate("B", "Chicken Bowl")],
                    query="chicken", query_embedding=None)
        neutral = rank_search_results(**args)
        boosted = rank_search_results(**args, fav_rec_nums={"B"})
        assert neutral[0]["rec_num"] == "A"
        assert boosted[0]["rec_num"] == "B"

    def test_available_today_tier_beats_a_higher_score(self):
        results = rank_search_results(
            candidates=[candidate("EXACT", "Chicken"), candidate("WEAK", "Chicken Salad Wrap")],
            query="chicken", query_embedding=None,
            available_today_rec_nums={"WEAK"},
        )
        assert results[0]["rec_num"] == "WEAK"

    def test_results_are_capped_at_50(self):
        results = rank_search_results(
            candidates=[candidate(f"R{i}", "Chicken") for i in range(60)],
            query="chicken", query_embedding=None,
        )
        assert len(results) == 50

    def test_embeddings_are_stripped_from_output(self):
        results = rank_search_results(
            candidates=[candidate("A", "Chicken", embedding=[0.1, 0.2, 0.3])],
            query="chicken", query_embedding=[0.1, 0.2, 0.3],
        )
        assert "embedding" not in results[0]

    def test_empty_candidates_returns_empty(self):
        assert rank_search_results(candidates=[], query="chicken", query_embedding=None) == []
