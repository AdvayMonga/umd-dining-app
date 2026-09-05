"""Dietary icon allowlist.

UMD added a `pea_protein` nutri-icon; the app renders anything outside its
known set as an allergen pill, so unknown icons must be dropped at ingest.
Production scrapes run through lambda/scraper_core.py, so both parsers are
tested — a fix applied to only one is the bug that shipped once already.
"""
import importlib.util
from pathlib import Path

import pytest

import scraper


def _load_lambda_scraper():
    """Load lambda/scraper_core.py by path: it shares module names with the API."""
    path = Path(__file__).resolve().parent.parent / "lambda" / "scraper_core.py"
    spec = importlib.util.spec_from_file_location("lambda_scraper_core", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


scraper_core = _load_lambda_scraper()

MENU_HTML = """
<html><body>
  <a href="#pane-1">Lunch</a>
  <div class="tab-pane" id="pane-1">
    <div class="card">
      <h3 class="card-title">Grill</h3>
      <div class="menu-item-row">
        <a class="menu-item-name" href="label.aspx?RecNumAndPort=12345">Veggie Burger</a>
        <img class="nutri-icon" alt="vegan">
        <img class="nutri-icon" alt="pea_protein">
        <img class="nutri-icon" alt="Contains soy">
      </div>
    </div>
  </div>
</body></html>
"""

PARSERS = [pytest.param(scraper.parse_menu_page, id="api-scraper"),
           pytest.param(scraper_core.parse_menu_page, id="lambda-scraper")]


@pytest.mark.parametrize("parse", PARSERS)
def test_unknown_icons_are_dropped(parse):
    items = parse(MENU_HTML, "19", "9/5/2026")
    assert len(items) == 1
    assert items[0]["dietary_icons"] == ["vegan", "Contains soy"]


@pytest.mark.parametrize("parse", PARSERS)
def test_known_item_fields_are_parsed(parse):
    item = parse(MENU_HTML, "19", "9/5/2026")[0]
    assert item["name"] == "Veggie Burger"
    assert item["rec_num"] == "12345"
    assert item["station"] == "Grill"
    assert item["meal_period"] == "Lunch"
    assert item["dining_hall_id"] == "19"


@pytest.mark.parametrize("parse", PARSERS)
def test_missing_tab_panes_yields_nothing_rather_than_garbage(parse):
    assert parse("<html><body><p>maintenance</p></body></html>", "19", "9/5/2026") == []


def test_both_parsers_share_the_same_allowlist():
    assert scraper.KNOWN_ICONS == scraper_core.KNOWN_ICONS


def test_allowlist_covers_the_icons_the_app_renders():
    assert {"vegan", "vegetarian", "HalalFriendly"} <= scraper.KNOWN_ICONS
    assert "pea_protein" not in scraper.KNOWN_ICONS
