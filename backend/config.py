import os
from dotenv import load_dotenv

load_dotenv()

class Settings:
    GOOGLE_API_KEY: str = os.getenv("GOOGLE_API_KEY", "")
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
    SUPABASE_KEY: str = os.getenv("SUPABASE_KEY", "")

    if not GOOGLE_API_KEY or not SUPABASE_URL or not SUPABASE_KEY:
        raise ValueError("Missing environment variables. Check your .env file.")

settings = Settings()