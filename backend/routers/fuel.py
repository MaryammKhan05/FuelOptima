"""
routers/fuel.py
- Scrapes current petrol/diesel prices from OGRA
- Calculates total trip cost from distance + vehicle efficiency
"""
import re
from datetime import datetime, timezone

import requests
from bs4 import BeautifulSoup
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()

# ---------- Simple in-memory cache ----------
# Fuel prices change at most once a day, so we don't scrape on every request.
_price_cache = {"petrol": None, "diesel": None, "updated_at": None}


# ---------- Fuel price scraping ----------
OGRA_URL = "https://ogra.org.pk/"


def _scrape_ogra_prices() -> dict:
    """
    Visit OGRA homepage and pull current petrol/diesel prices.
    The page structure may change over time — update the regex if needed.
    """
    try:
        r = requests.get(
            OGRA_URL,
            timeout=10,
            headers={"User-Agent": "Mozilla/5.0 (FuelOptima FYP project)"},
        )
        r.raise_for_status()
    except requests.RequestException as e:
        raise HTTPException(status_code=502, detail=f"OGRA unreachable: {e}")
    # --- DEBUG: save raw HTML so we can inspect it ---
    with open("ogra_debug.html", "w", encoding="utf-8") as f:
        f.write(r.text)
    # --- END DEBUG ---
    soup = BeautifulSoup(r.text, "html.parser")
    text = soup.get_text(" ", strip=True)

    # Look for "Petrol" followed by a number (2-4 digits, optional decimal)
    petrol_match = re.search(
        r"Petrol[^0-9]{0,40}([0-9]{2,4}\.?[0-9]{0,2})", text, re.IGNORECASE
    )
    diesel_match = re.search(
        r"(?:HSD|Diesel)[^0-9]{0,40}([0-9]{2,4}\.?[0-9]{0,2})",
        text,
        re.IGNORECASE,
    )

    petrol = float(petrol_match.group(1)) if petrol_match else None
    diesel = float(diesel_match.group(1)) if diesel_match else None

    if petrol is None or diesel is None:
        raise HTTPException(
            status_code=502,
            detail="Could not parse fuel prices from OGRA page. "
                   "The site structure may have changed.",
        )

    return {"petrol": petrol, "diesel": diesel}


@router.get("/prices")
def get_prices(force_refresh: bool = False):
    """
    Return current petrol and diesel prices (PKR per liter).
    Cached in memory after first call — pass ?force_refresh=true to re-scrape.
    """
    if force_refresh or _price_cache["petrol"] is None:
        prices = _scrape_ogra_prices()
        _price_cache.update(
            {**prices, "updated_at": datetime.now(timezone.utc).isoformat()}
        )
    return _price_cache


# ---------- Trip cost calculation ----------
class TripCostRequest(BaseModel):
    distance_km: float
    vehicle_efficiency_km_per_l: float   # e.g. 14.0 for a typical Corsa
    fuel_type: str                        # "petrol" or "diesel"
    # Optional multipliers from the research paper formulas:
    traffic_multiplier: float = 1.0       # 1.0 smooth, 1.1 moderate, 1.25 heavy
    speed_multiplier: float = 1.0         # 1.0 ideal, 1.3 slow, 1.2 very fast


@router.post("/trip-cost")
def trip_cost(req: TripCostRequest):
    """
    Compute estimated fuel consumption and total trip cost.

    Formula (from research papers cited in the proposal):
        BaseFuel   = Distance / VehicleEfficiency
        FinalFuel  = BaseFuel x TrafficMultiplier x SpeedMultiplier
        TripCost   = FinalFuel x FuelPrice
    """
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
    }