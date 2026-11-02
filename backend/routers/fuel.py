"""
routers/fuel.py
- Scrapes fuel prices from Business Recorder.
- Saves successful scrapes to Supabase.
- Falls back to the last saved price in Supabase if scraping fails.
- Uses a trained Machine Learning model (fuel_model.pkl) for trip cost prediction.
"""
import re
import os
import joblib
import pandas as pd
import numpy as np
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

# ============================================================
# LOAD THE MACHINE LEARNING MODEL
# ============================================================
MODEL_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "fuel_model.pkl")
ml_model = None
try:
    if os.path.exists(MODEL_PATH):
        ml_model = joblib.load(MODEL_PATH)
        print(f"[OK] ML Model loaded successfully from {MODEL_PATH}")
    else:
        print(f"[WARN] ML Model not found at {MODEL_PATH}. Falling back to static formula.")
except Exception as e:
    print(f"[ERROR] Could not load ML Model: {e}")

def _get_last_saved_price(fuel_type: str) -> float:
    try:
        response = supabase.table("fuel_prices")\
            .select("price_pkr")\
            .eq("fuel_type", fuel_type)\
            .order("created_at", desc=True)\
            .limit(1)\
            .execute()
        if response.data and len(response.data) > 0:
            return float(response.data[0]["price_pkr"])
    except Exception as e:
        print(f"[WARN] Supabase error: {e}")
    return 0.0

def _save_price_to_db(fuel_type: str, price: float, source: str):
    try:
        supabase.table("fuel_prices").insert({
            "fuel_type": fuel_type,
            "price_pkr": price,
            "source": source
        }).execute()
    except Exception as e:
        print(f"[WARN] Failed to save to Supabase: {e}")

def _scrape_news_prices() -> dict:
    petrol, diesel = None, None
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept-Language": "en-US,en;q=0.9",
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
            _save_price_to_db("petrol", petrol, "Business Recorder Scrape")
            _save_price_to_db("diesel", diesel, "Business Recorder Scrape")
            return {"petrol": petrol, "diesel": diesel, "source": "Live Scrape"}
    except requests.RequestException:
        pass

    if petrol is None or diesel is None:
        petrol = _get_last_saved_price("petrol")
        diesel = _get_last_saved_price("diesel")
        if petrol == 0.0 or diesel == 0.0:
            raise HTTPException(503, "Scraper failed AND database is empty.")
        return {"petrol": petrol, "diesel": diesel, "source": "Supabase (Cached Fallback)"}

@router.get("/prices")
def get_prices(force_refresh: bool = False):
    if force_refresh or _price_cache["petrol"] is None:
        prices = _scrape_news_prices()
        _price_cache.update({**prices, "updated_at": datetime.now(timezone.utc).isoformat()})
    return _price_cache

# ============================================================
# NEW TEST ENDPOINT FOR AI (Click and Test!)
# ============================================================
@router.get("/test-ai")
def test_ai():
    """A simple test endpoint to prove the AI model is working."""
    if ml_model is None:
        return {"status": "error", "message": "ML model not loaded. Check file path."}
    
    try:
        # 5 main + 4 engineered = 9 features
        features = ['Vehicle_Speed_km_per_h', 'Engine_RPM_RPM', 'Absolute_Load_pct', 
                    'Short_Term_Fuel_Trim_Bank_1_pct', 'RPM_per_Speed', 
                    'Speed_squared', 'Load_times_RPM', 'Is_Idle']
        
        # Sample inputs (Speed=60, RPM=2000, Load=40, Trim=2)
        speed, rpm, load, trim = 60.0, 2000.0, 40.0, 2.0
        rpm_per_speed = rpm / (speed + 1)
        speed_squared = speed ** 2
        load_times_rpm = load * rpm
        is_idle = 0

        input_data = pd.DataFrame([[
            speed, rpm, load, trim,
            rpm_per_speed, speed_squared, load_times_rpm, is_idle
        ]], columns=features)

        predicted_fuel_rate = float(ml_model.predict(input_data)[0])
        
        return {
            "status": "success",
            "test_inputs": {"speed": speed, "rpm": rpm, "load": load, "trim": trim},
            "predicted_fuel_rate_L_per_hr": round(predicted_fuel_rate, 3),
            "message": "If you see this, AI is working perfectly!"
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ============================================================
# ACTUAL TRIP COST (For Flutter)
# ============================================================
class TripCostRequest(BaseModel):
    distance_km: float
    fuel_type: str
    vehicle_efficiency_km_per_l: float = 12.0
    traffic_multiplier: float = 1.0
    speed_multiplier: float = 1.0
    avg_speed_kmh: float = 40.0
    avg_rpm: float = 2000.0
    avg_engine_load: float = 30.0
    avg_maf: float = 10.0
    avg_fuel_trim: float = 0.0

@router.post("/trip-cost")
def trip_cost(req: TripCostRequest):
    if req.fuel_type not in ("petrol", "diesel"):
        raise HTTPException(400, "fuel_type must be 'petrol' or 'diesel'")

    fuel_liters = 0.0
    method_used = "Static Formula"

    if ml_model is not None:
        try:
            features = ['Vehicle_Speed_km_per_h', 'Engine_RPM_RPM', 'Absolute_Load_pct', 
                        'Short_Term_Fuel_Trim_Bank_1_pct', 'RPM_per_Speed', 
                        'Speed_squared', 'Load_times_RPM', 'Is_Idle']
            
            rpm_per_speed = req.avg_rpm / (req.avg_speed_kmh + 1)
            speed_squared = req.avg_speed_kmh ** 2
            load_times_rpm = req.avg_engine_load * req.avg_rpm
            is_idle = 1 if (req.avg_speed_kmh == 0 and req.avg_rpm > 0) else 0

            input_data = pd.DataFrame([[
                req.avg_speed_kmh, req.avg_rpm, req.avg_engine_load, req.avg_fuel_trim,
                rpm_per_speed, speed_squared, load_times_rpm, is_idle
            ]], columns=features)

            predicted_fuel_rate_lhr = float(ml_model.predict(input_data)[0])
            trip_duration_hr = req.distance_km / (req.avg_speed_kmh if req.avg_speed_kmh > 0 else 1)
            fuel_liters = predicted_fuel_rate_lhr * trip_duration_hr
            method_used = "Machine Learning Model"
        except Exception as e:
            print(f"[ERROR] ML Prediction failed: {e}")
            fuel_liters = 0.0

    if fuel_liters <= 0.0 or method_used == "Static Formula":
        if req.vehicle_efficiency_km_per_l <= 0:
            raise HTTPException(400, "vehicle_efficiency must be > 0")
        base_fuel_l = req.distance_km / req.vehicle_efficiency_km_per_l
        fuel_liters = base_fuel_l * req.traffic_multiplier * req.speed_multiplier

    prices = get_prices()
    price_per_l = prices[req.fuel_type]
    total_cost_pkr = fuel_liters * price_per_l

    return {
        "distance_km": req.distance_km,
        "predicted_fuel_l": round(fuel_liters, 3),
        "price_per_l_pkr": price_per_l,
        "total_cost_pkr": round(total_cost_pkr, 2),
        "fuel_type": req.fuel_type,
        "prediction_method": method_used,
        "price_updated_at": prices["updated_at"],
        "price_source": prices["source"]
    }