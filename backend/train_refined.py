import pandas as pd
import numpy as np
import glob
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import xgboost as xgb
import joblib

# ============================================================
# STEP 1: READ PARQUET FILES
# ============================================================
folder_path = r"C:\FuelOptima\dataset_refined\content\ved_phase_1\*.parquet"
file_list = glob.glob(folder_path)

print(f"Found {len(file_list)} Parquet files. Reading them...")

features = [
    'Vehicle_Speed_km_per_h', 
    'Engine_RPM_RPM', 
    'Absolute_Load_pct', 
    'Short_Term_Fuel_Trim_Bank_1_pct'
]
target = 'Calculated_Fuel_Rate_L_hr'

all_data = []
for file in file_list:
    try:
        df = pd.read_parquet(file)
        required_cols = features + ['MAF_g_per_sec']
        if all(col in df.columns for col in required_cols):
            all_data.append(df[required_cols].copy())
    except Exception:
        pass

df_final = pd.concat(all_data, ignore_index=True)
df_final = df_final.loc[:, ~df_final.columns.duplicated()]
print(f"Total rows successfully read: {len(df_final)}")

# ============================================================
# STEP 2: CALCULATE ACTUAL FUEL RATE
# ============================================================
df_final[target] = (
    df_final['MAF_g_per_sec'] / 14.7 / 750 * 3600
) * (1 + df_final['Short_Term_Fuel_Trim_Bank_1_pct'] / 100)

# ============================================================
# STEP 3: FEATURE ENGINEERING (The Magic Step)
# ============================================================
print("Creating new smart features...")

# 1. Gear Estimator (RPM per Speed)
df_final['RPM_per_Speed'] = df_final['Engine_RPM_RPM'] / (df_final['Vehicle_Speed_km_per_h'] + 1)

# 2. Aerodynamic Drag Proxy (Speed squared)
df_final['Speed_squared'] = df_final['Vehicle_Speed_km_per_h'] ** 2

# 3. Engine Power Proxy (Load * RPM)
df_final['Load_times_RPM'] = df_final['Absolute_Load_pct'] * df_final['Engine_RPM_RPM']

# 4. Idle Indicator (1 if stopped but engine on, else 0)
df_final['Is_Idle'] = ((df_final['Vehicle_Speed_km_per_h'] == 0) & (df_final['Engine_RPM_RPM'] > 0)).astype(int)

# Update our features list to include the new engineered features
features = features + ['RPM_per_Speed', 'Speed_squared', 'Load_times_RPM', 'Is_Idle']

# ============================================================
# STEP 4: SMART CLEANING
# ============================================================
for col in features + [target]:
    df_final[col] = pd.to_numeric(df_final[col], errors='coerce')

df_final = df_final.fillna(0)
df_final = df_final[df_final[target] > 0]

# Remove extreme outliers
for col in features + [target]:
    Q1 = df_final[col].quantile(0.001)
    Q3 = df_final[col].quantile(0.999)
    df_final = df_final[(df_final[col] >= Q1) & (df_final[col] <= Q3)]

print(f"Final clean rows ready for training: {len(df_final)}")

if len(df_final) > 1000000:
    print("Downsampling to 1,000,000 rows...")
    df_final = df_final.sample(n=1000000, random_state=42).reset_index(drop=True)

# ============================================================
# STEP 5: TRAIN / TEST SPLIT
# ============================================================
X = df_final[features]
y = df_final[target]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# ============================================================
# STEP 6: TRAIN MODELS
# ============================================================
print("\nTraining Random Forest model...")
rf_model = RandomForestRegressor(n_estimators=50, max_depth=15, random_state=42, n_jobs=-1)
rf_model.fit(X_train, y_train)
rf_pred = rf_model.predict(X_test)
print(f"RF Results -> R2: {r2_score(y_test, rf_pred):.4f} | MAE: {mean_absolute_error(y_test, rf_pred):.4f}")

print("\nTraining XGBoost model...")
xgb_model = xgb.XGBRegressor(n_estimators=100, max_depth=8, learning_rate=0.1, random_state=42, n_jobs=-1)
xgb_model.fit(X_train, y_train)
xgb_pred = xgb_model.predict(X_test)
print(f"XGB Results -> R2: {r2_score(y_test, xgb_pred):.4f} | MAE: {mean_absolute_error(y_test, xgb_pred):.4f}")

# ============================================================
# STEP 7: SAVE THE BEST MODEL
# ============================================================
if r2_score(y_test, xgb_pred) > r2_score(y_test, rf_pred):
    print("\nXGBoost performed better. Saving XGBoost...")
    joblib.dump(xgb_model, "fuel_model.pkl")
else:
    print("\nRandom Forest performed better. Saving Random Forest...")
    joblib.dump(rf_model, "fuel_model.pkl")