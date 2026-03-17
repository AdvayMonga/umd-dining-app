# UMD Dining API

A REST API that scrapes and serves University of Maryland dining hall menus and nutrition information.

## Features

- Scrapes menus from UMD dining halls (Yahentamitsi, 251 North, South Campus Diner)
- Fetches and caches nutrition info, allergens, and ingredients per item
- Search for food items by name

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dining-halls` | List all dining halls |
| GET | `/api/menu?date=...&dining_hall_id=...` | Get menu items (filterable) |
| GET | `/api/nutrition?rec_num=...` | Get nutrition info for a food item |
| GET | `/api/search?q=...` | Search food items by name |
| POST | `/api/scrape?date=...` | Scrape menus for a given date |