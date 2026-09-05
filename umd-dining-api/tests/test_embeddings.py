"""Vector helpers used by ranking and similar-food computation."""
import pytest

from embeddings import build_embedding_text, compute_centroid, cosine_similarity


class TestCosineSimilarity:
    def test_identical_vectors(self):
        assert cosine_similarity([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]) == pytest.approx(1.0)

    def test_orthogonal_vectors(self):
        assert cosine_similarity([1.0, 0.0], [0.0, 1.0]) == pytest.approx(0.0)

    def test_opposite_vectors(self):
        assert cosine_similarity([1.0, 0.0], [-1.0, 0.0]) == pytest.approx(-1.0)

    def test_magnitude_does_not_matter(self):
        assert cosine_similarity([1.0, 1.0], [5.0, 5.0]) == pytest.approx(1.0)

    def test_zero_vector_returns_zero_instead_of_dividing_by_zero(self):
        assert cosine_similarity([0.0, 0.0], [1.0, 2.0]) == 0.0


class TestCentroid:
    def test_mean_of_vectors(self):
        assert compute_centroid([[0.0, 0.0], [2.0, 4.0]]) == pytest.approx([1.0, 2.0])

    def test_single_vector_is_itself(self):
        assert compute_centroid([[1.5, -2.5]]) == pytest.approx([1.5, -2.5])

    def test_empty_returns_none(self):
        assert compute_centroid([]) is None


class TestEmbeddingText:
    def test_includes_name_ingredients_and_allergens(self):
        text = build_embedding_text({
            "name": "Chicken Tikka", "ingredients": "chicken, yogurt", "allergens": "dairy",
        })
        assert "Chicken Tikka" in text and "chicken, yogurt" in text and "dairy" in text

    def test_optional_fields_omitted_when_absent(self):
        assert build_embedding_text({"name": "Rice"}).strip() == "Rice."
