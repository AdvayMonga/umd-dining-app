"""Core scraping logic for UMD dining halls. Used by Lambda handler."""

import requests
from bs4 import BeautifulSoup
from datetime import datetime

BASE_URL = "https://nutrition.umd.edu"

DINING_HALLS = {
    "19": {"name": "Yahentamitsi Dining Hall", "location": "South Campus"},
    "51": {"name": "251 North", "location": "North Campus"},
    "16": {"name": "South Campus Diner", "location": "South Campus"},
}


def get_menu_page(location_num, date):
    url = f"{BASE_URL}/?locationNum={location_num}&dtdate={date}"
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.text


def parse_menu_page(html, dining_hall_id, date):
    soup = BeautifulSoup(html, 'html.parser')
    items = []

    # Determine meal period labels from the tab nav
    tab_labels = {}
    tabs = soup.find('ul', class_='nav-tabs')
    if tabs:
        for tab_link in tabs.find_all('a', role='tab'):
            pane_id = (tab_link.get('aria-controls') or '').strip()
            label = tab_link.get_text(strip=True)
            if pane_id and label:
                tab_labels[pane_id] = label

    # Parse food items from each tab pane, grouped by station (card)
    panes = soup.find_all('div', class_='tab-pane')
    for pane in panes:
        pane_id = pane.get('id', '')
        meal_period = tab_labels.get(pane_id, 'Unknown')

        for card in pane.find_all('div', class_='card'):
            title_el = card.find('h5', class_='card-title')
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


def scrape_dining_hall(db, location_num, date):
    items = parse_menu_page(get_menu_page(location_num, date), location_num, date)

    for item in items:
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
            upsert=True,
        )

        db.foods.update_one(
            {"rec_num": item["rec_num"]},
            {"$setOnInsert": {
                "rec_num": item["rec_num"],
                "name": item["name"],
                "nutrition": {},
                "allergens": "",
                "ingredients": "",
                "nutrition_fetched": False,
            }},
            upsert=True,
        )

    return items


def scrape_all_dining_halls(db, date):
    # Delete old menus (dates before today)
    all_menus = db.menus.distinct("date")
    for menu_date in all_menus:
        try:
            parsed = datetime.strptime(menu_date, '%m/%d/%Y')
            if parsed.date() < datetime.now().date():
                db.menus.delete_many({"date": menu_date})
        except ValueError:
            pass

    # Delete today's menus for a fresh scrape
    db.menus.delete_many({"date": date})

    all_items = []
    for location_num in DINING_HALLS:
        items = scrape_dining_hall(db, location_num, date)
        all_items.extend(items)

    return all_items
