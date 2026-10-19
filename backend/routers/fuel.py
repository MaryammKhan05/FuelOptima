"""
routers/fuel.py
- Scrapes fuel prices from Business Recorder.
- Saves successful scrapes to Supabase.
- Falls back to the last saved price in Supabase if scraping fails.
"""
import re
from datetime import datetime, timezone
import requests
from bs4 import BeautifulSoup
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from supabase import create_client, Client

from config import settings

router = APIRouter()

# Initialize Supabase client
print(f"DEBUG: Trying to connect to Supabase at URL: {settings.SUPABASE_URL}")
print(f"DEBUG: Using key starting with: {settings.SUPABASE_KEY[:15]}...")
supabase: Client = create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)

_price_cache = {"petrol": None, "diesel": None, "updated_at": None, "source": None}

SCRAPE_URL = "https://www.brecorder.com/search?q=petrol+price"

def _get_last_saved_price(fuel_type: str) -> float:
    """Fetch the most recent price from Supabase."""
    try:
        response = supabase.table("fuel_prices")\
            .select("price_pkr")\
            .eq("fuel_type", fuel_type)\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()
        
        print(f"DEBUG: Supabase returned for {fuel_type}: {response.data}")
        
        if response.data and len(response.data) > 0:
            return float(response.data[0]["price_pkr"])
    except Exception as e:
        print(f"[WARN] Supabase error: {e}")
    return 0.0

def _save_price_to_db(fuel_type: str, price: float, source: str):
    """Save the newly scraped price to Supabase."""
    try:
        supabase.table("fuel_prices").insert({
            "fuel_type": fuel_type,
            "price_pkr": price,
            "source": source
        }).execute()
        print(f"[OK] Saved {fuel_type} to Supabase: {price}")
    except Exception as e:
        print(f"[WARN] Failed to save to Supabase: {e}")

def _scrape_news_prices() -> dict:
    """Scrape Business Recorder. If it fails, use the last database price."""
    petrol, diesel = None, None
    
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept-Language": "en-US,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
        }
        r = requests.get(SCRAPE_URL, timeout=10, headers=headers)
        r.raise_for_status()
        soup = BeautifulSoup(r.text, "html.parser")
        text = soup.get_text(" ", strip=True)

        petrol_match = re.search(r"petrol[^0-9]{0,50}(2[0-9]{2}\.[0-9]{2})", text, re.IGNORECASE)
        diesel_match = re.search(r"diesel[^0-9]{0,50}(2[0-9]{2}\.[0-9]{2})", text, re.IGNORECASE)

        if petrol_match and diesel_match:
            petrol = float(petrol_match.group(1))
            diesel = float(diesel_match.group(1))
            
            print(f"[OK] Scraped from News: Petrol={petrol}, Diesel={diesel}")
            _save_price_to_db("petrol", petrol, "Business Recorder Scrape")
            _save_price_to_db("diesel", diesel, "Business Recorder Scrape")
            return {"petrol": petrol, "diesel": diesel, "source": "Live Scrape"}
        else:
            print("[WARN] Scraper didn't find numbers in the text. Falling back to DB.")
            
    except requests.RequestException as e:
        print(f"[WARN] Scraper failed: {e}. Fetching from DB...")

    # If scraping failed, fetch from Supabase
    if petrol is None or diesel is None:
        petrol = _get_last_saved_price("petrol")
        diesel = _get_last_saved_price("diesel")
        
        if petrol == 0.0 or diesel == 0.0:
            raise HTTPException(
                status_code=503, 
                detail="Scraper failed AND database is empty. Please insert a manual price in Supabase."
            )
            
        return {"petrol": petrol, "diesel": diesel, "source": "Supabase (Cached Fallback)"}

@router.get("/prices")
def get_prices(force_refresh: bool = False):
    if force_refresh or _price_cache["petrol"] is None:
        prices = _scrape_news_prices()
        _price_cache.update({**prices, "updated_at": datetime.now(timezone.utc).isoformat()})
    return _price_cache

# ---------- Trip cost calculation ----------
class TripCostRequest(BaseModel):
    distance_km: float
    vehicle_efficiency_km_per_l: float
    fuel_type: str
    traffic_multiplier: float = 1.0
    speed_multiplier: float = 1.0

@router.post("/trip-cost")
def trip_cost(req: TripCostRequest):
    if req.vehicle_efficiency_km_per_l <= 0:
        raise HTTPException(400, "vehicle_efficiency_km_per_l must be > 0")
    if req.fuel_type not in ("petrol", "diesel"):
        raise HTTPException(400, "fuel_type must be 'petrol' or 'diesel'")

    base_fuel_l = req.distance_km / req.vehicle_efficiency_km_per_l
    final_fuel_l = base_fuel_l * req.traffic_multiplier * req.speed_multiplier

    prices = get_prices()
    price_per_l = prices[req.fuel_type]
    total_cost_pkr = final_fuel_l * price_per_l

    return {
        "distance_km": req.distance_km,
        "base_fuel_l": round(base_fuel_l, 3),
        "final_fuel_l": round(final_fuel_l, 3),
        "price_per_l_pkr": price_per_l,
        "total_cost_pkr": round(total_cost_pkr, 2),
        "fuel_type": req.fuel_type,
        "price_updated_at": prices["updated_at"],
        "price_source": prices["source"]
    }