from datetime import datetime

class DiningHall:
    def __init__(self, name, hall_id, location=None):
        self.name = name
        self.hall_id = hall_id
        self.location = location

    def to_dict(self):
        return {
            'name': self.name,
            'hall_id': self.hall_id,
            'location': self.location
        }


class MenuItem:

    def __init__(self, name, dining_hall_id, meal_period, date,
                 station=None, is_entree=True, nutrition=None,
                 allergens=None, ingredients=None):
        self.name = name
        self.dining_hall_id = dining_hall_id
        self.meal_period = meal_period 
        self.date = date
        self.station = station
        self.is_entree = is_entree
        self.nutrition = nutrition or {}
        self.allergens = allergens or []
        self.ingredients = ingredients or []
        self.created_at = datetime.now()

    def to_dict(self):
        return {
            'name': self.name,
            'dining_hall_id': self.dining_hall_id,
            'meal_period': self.meal_period,
            'date': self.date,
            'station': self.station,
            'is_entree': self.is_entree,
            'nutrition': self.nutrition,
            'allergens': self.allergens,
            'ingredients': self.ingredients,
            'created_at': self.created_at
        }
