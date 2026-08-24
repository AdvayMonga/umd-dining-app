# UMD Dining

An iOS app for browsing University of Maryland dining hall menus, with personalized food rankings, nutrition info, and dietary filtering.

## Structure

- **`umd-dining-app/`** — SwiftUI iOS app
- **`umd-dining-api/`** — Python/FastAPI backend that scrapes and serves dining data

## Features

- Browse menus across all three dining halls (Yahentamitsi, 251 North, South Campus Diner)
- Personalized food rankings based on your taste profile
- Nutrition details, allergens, and ingredients per item
- Filter by dining hall, dietary preference (vegetarian/vegan), and allergens
- Search across all menu items
- Favorite foods and stations

## Backend

See [`umd-dining-api/README.md`](umd-dining-api/README.md) for API setup and endpoints.

## Deployment

The API deploys to AWS Elastic Beanstalk automatically when changes under
`umd-dining-api/` land on `main` (see `.github/workflows/deploy-api.yml`), and
can also be triggered manually from the Actions tab. Every deploy is labeled
with its commit SHA; roll back by redeploying a previous version from the EB
console. The iOS app ships via App Store Connect (Xcode → Product → Archive).
