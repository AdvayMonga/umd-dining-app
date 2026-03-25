import re
import time
import requests
from bs4 import BeautifulSoup
from pymongo import MongoClient
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv

load_dotenv()

# MongoDB connection
mongo_uri = os.getenv('MONGO_URI')
client = MongoClient(mongo_uri)
db = client.get_database()

# Base URL
BASE_URL = "https://nutrition.umd.edu"

# Known dining halls (locationNum -> name)
DINING_HALLS = {
    "19": {"name": "Yahentamitsi Dining Hall", "location": "South Campus"},
    "51": {"name": "251 North", "location": "North Campus"},
    "16": {"name": "South Campus Diner", "location": "South Campus"},
}

def get_menu_page(location_num, date):
    url = f"{BASE_URL}/?locationNum={location_num}&dtdate={date}"
    response = requests.get(url)
    response.raise_for_status()

    return response.text

def parse_menu_page(html, dining_hall_id, date):
    soup = BeautifulSoup(html, 'html.parser')
    items = []

    # Determine meal period labels from tab links (href="#pane-N")
    tab_labels = {}
    for a in soup.find_all('a', href=lambda x: x and x.startswith('#')):
        href = a.get('href', '')
        pane_id = href.lstrip('#')
        label = a.get_text(strip=True)
        if pane_id and label:
            tab_labels[pane_id] = label

    # Parse food items from each tab pane, grouped by station (card)
    panes = soup.find_all('div', class_='tab-pane')
    for pane in panes:
        pane_id = pane.get('id', '')
        meal_period = tab_labels.get(pane_id, 'Unknown')

        for card in pane.find_all('div', class_='card'):
            title_el = card.find('h3', class_='card-title')
            station = title_el.get_text(strip=True) if title_el else 'Unknown'

            for row in card.find_all('div', class_='menu-item-row'):
                link = row.find('a', class_='menu-item-name')
                if not link:
                    continue
                href = link.get('href', '')
                if 'label.aspx' not in href:
                    continue

                name = link.get_text(strip=True)
                rec_num = href.split('RecNumAndPort=')[-1]

                # Dietary icons (vegan, vegetarian, dairy, gluten, etc.)
                icons = [img.get('alt', '') for img in row.find_all('img', class_='nutri-icon')]

                items.append({
                    "name": name,
                    "dining_hall_id": dining_hall_id,
                    "date": date,
                    "rec_num": rec_num,
                    "meal_period": meal_period,
                    "station": station,
                    "dietary_icons": icons,
                })

    # Fallback: if no tab panes found, grab all links
    if not panes:
        for link in soup.find_all('a', href=True):
            href = link.get('href')
            if 'label.aspx' not in href:
                continue
            name = link.get_text(strip=True)
            rec_num = href.split('RecNumAndPort=')[-1]
            items.append({
                "name": name,
                "dining_hall_id": dining_hall_id,
                "date": date,
                "rec_num": rec_num,
                "meal_period": "Unknown",
                "station": "Unknown",
                "dietary_icons": [],
            })

    return items


def get_nutrition_info(rec_num):
    url = f"{BASE_URL}/label.aspx?RecNumAndPort={rec_num}"
    response = requests.get(url)
    response.raise_for_status()

    soup = BeautifulSoup(response.text, 'html.parser')

    nutrition = {}

    # Servings per container (its own div)
    serv_per = soup.find('div', class_='nutfactsservpercont')
    if serv_per:
        nutrition['Servings Per Container'] = serv_per.get_text(strip=True)

    # Serving size (second div has the value, first just says "Serving size")
    serv_divs = soup.find_all('div', class_='nutfactsservsize')
    for div in serv_divs:
        text = div.get_text(strip=True)
        if text and text.lower() != 'serving size':
            nutrition['Serving Size'] = text
            break

    # Calories (in a <p> tag after "Calories per serving")
    for p in soup.find_all('p'):
        if p.get_text(strip=True) == 'Calories per serving':
            next_p = p.find_next_sibling('p')
            if next_p:
                nutrition['Calories'] = next_p.get_text(strip=True)
            break

    # All nutrient spans (bolded and non-bolded)
    nutrients = soup.find_all('span', class_='nutfactstopnutrient')
    seen_keys = set(nutrition.keys())

    for nutrient in nutrients:
        text = nutrient.get_text(strip=True).replace('\xa0', ' ')
        if not text or re.match(r'^\d+%$', text) or text.startswith('Includes'):
            continue

        label = nutrient.find('b')
        if label:
            name = label.get_text(strip=True).rstrip('.')
            value = text.replace(label.get_text(strip=True), '').strip()
        else:
            match = re.match(r'^([A-Za-z\s\-\.]+?)\s*([\d\.]+.*)$', text)
            if not match:
                continue
            name = match.group(1).strip().rstrip('.')
            value = match.group(2).strip()

        if not name or not value:
            continue

        if name == 'Calories':
            value = value.replace('kcal', '').strip()

        if name not in seen_keys:
            seen_keys.add(name)
            nutrition[name] = value

    ingredients = soup.find('span', class_='labelingredientsvalue')
    if ingredients:
        nutrition['ingredients'] = ingredients.get_text(strip=True)

    allergens = soup.find('span', class_='labelallergensvalue')
    if allergens:
        nutrition['allergens'] = allergens.get_text(strip=True)

    return nutrition

def scrape_dining_hall(location_num, date):
    """Scrape a dining hall's menu for a date. Adds menu entries, food stubs, and pre-fetches nutrition."""
    items = parse_menu_page(get_menu_page(location_num, date), location_num, date)

    for item in items:
        # Add to menus collection
        menu_doc = {
            "date": date,
            "dining_hall_id": location_num,
            "rec_num": item["rec_num"],
            "meal_period": item["meal_period"],
            "station": item["station"],
            "dietary_icons": item["dietary_icons"],
        }
        db.menus.update_one(
            {"date": date, "dining_hall_id": location_num, "rec_num": item["rec_num"], "meal_period": item["meal_period"]},
            {"$set": menu_doc},
            upsert=True
        )

        # Add to foods collection if not already there
        db.foods.update_one(
            {"rec_num": item["rec_num"]},
            {"$setOnInsert": {
                "rec_num": item["rec_num"],
                "name": item["name"],
                "nutrition": {},
                "allergens": "",
                "ingredients": "",
                "nutrition_fetched": False
            }},
            upsert=True
        )

    # Pre-fetch nutrition for items that don't have it yet
    for item in items:
        food = db.foods.find_one({"rec_num": item["rec_num"]})
        if food and not food.get("nutrition_fetched"):
            try:
                fetch_and_cache_nutrition(item["rec_num"])
                time.sleep(0.5)  # Rate limit to avoid overwhelming UMD's site
            except Exception as e:
                print(f"Failed to fetch nutrition for {item['name']}: {e}")

    return items

def scrape_all_dining_halls(date):
    """Scrape all dining halls for a single date. Cleans menus older than 7 days."""
    # Delete menus older than 7 days
    cutoff = (datetime.now() - timedelta(days=7)).date()
    all_menus = db.menus.distinct("date")
    for menu_date in all_menus:
        try:
            parsed = datetime.strptime(menu_date, '%m/%d/%Y')
            if parsed.date() < cutoff:
                db.menus.delete_many({"date": menu_date})
        except ValueError:
            pass

    # Fresh scrape for the given date
    db.menus.delete_many({"date": date})

    all_items = []
    for location_num in DINING_HALLS:
        items = scrape_dining_hall(location_num, date)
        all_items.extend(items)

    return all_items


def scrape_full_week():
    """One-time scrape: today + 6 days ahead."""
    today = datetime.now()

    all_items = []
    for i in range(7):
        scrape_date = (today + timedelta(days=i)).strftime('%-m/%-d/%Y')
        items = scrape_all_dining_halls(scrape_date)
        all_items.extend(items)

    return all_items

def fetch_and_cache_nutrition(rec_num):
    """Fetch nutrition for a food item and cache it permanently. Returns the food document."""
    food = db.foods.find_one({"rec_num": rec_num})

    if food and food.get("nutrition_fetched"):
        return food

    nutrition_data = get_nutrition_info(rec_num)

    update = {
        "nutrition_fetched": True,
        "nutrition": {k: v for k, v in nutrition_data.items() if k not in ("ingredients", "allergens")},
        "allergens": nutrition_data.get("allergens", ""),
        "ingredients": nutrition_data.get("ingredients", ""),
    }

    db.foods.update_one(
        {"rec_num": rec_num},
        {"$set": update},
        upsert=True
    )

    return db.foods.find_one({"rec_num": rec_num})
