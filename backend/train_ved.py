import pandas as pd
import numpy as np
import glob
import csv
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
import xgboost as xgb
import joblib

folder_path = r"C:\FuelOptima\dataset\*.csv"
file_list = glob.glob(folder_path)

print(f"Found {len(file_list)} CSV files. Reading them safely...")

features = [
    'Vehicle Speed[km/h]', 
    'Engine RPM[RPM]', 
    'Absolute Load[%]', 
    'MAF[g/sec]',
    'Short Term Fuel Trim Bank 1[%]' 
]
target = 'Fuel Rate[L/hr]'

all_data = []
rows_per_file = 20000

for file in file_list:
    try:
        with open(file, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
            
            if headers and all(col in headers for col in features + [target]):
                temp_data = []
                for i, row in enumerate(reader):
                    if i >= rows_per_file:
                        break
                    try:
                        temp_row = [float(row[col]) for col in features + [target]]
                        temp_data.append(temp_row)
                    except (ValueError, TypeError):
                        continue 
                
                if temp_data:
                    df_temp = pd.DataFrame(temp_data, columns=features + [target])
                    all_data.append(df_temp)
    except Exception:
        pass

df_final = pd.concat(all_data, ignore_index=True)
print(f"Total combined rows read: {len(df_final)}")

for col in features + [target]:
    df_final[col] = pd.to_numeric(df_final[col], errors='coerce')

df_final = df_final.fillna(0)
df_final = df_final[df_final[target] > 0]
print(f"Rows after basic cleaning: {len(df_final)}")

for col in ['Vehicle Speed[km/h]', 'Engine RPM[RPM]', 'Fuel Rate[L/hr]']:
    Q1 = df_final[col].quantile(0.01)
    Q3 = df_final[col].quantile(0.99)
    df_final = df_final[(df_final[col] >= Q1) & (df_final[col] <= Q3)]

print(f"Final clean rows ready for training: {len(df_final)}")

X = df_final[features]
y = df_final[target]

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# ============================================================
# 1. RANDOM FOREST
# ============================================================
print("\nTraining Random Forest model...")
rf_model = RandomForestRegressor(n_estimators=100, max_depth=20, random_state=42, n_jobs=-1)
rf_model.fit(X_train, y_train)
rf_pred = rf_model.predict(X_test)

rf_mae = mean_absolute_error(y_test, rf_pred)
rf_rmse = np.sqrt(mean_squared_error(y_test, rf_pred))
rf_r2 = r2_score(y_test, rf_pred)

print(f"RF Results -> R2: {rf_r2:.4f} | MAE: {rf_mae:.4f} L/hr | RMSE: {rf_rmse:.4f} L/hr")

# ============================================================
# 2. XGBOOST (With Clean Feature Names)
# ============================================================
print("\nTraining XGBoost model...")

X_train_xgb = X_train.copy()
X_test_xgb = X_test.copy()

clean_names = [name.replace('[', '_').replace(']', '').replace('/', '_').strip() for name in X_train.columns]
X_train_xgb.columns = clean_names
X_test_xgb.columns = clean_names

xgb_model = xgb.XGBRegressor(n_estimators=100, max_depth=6, learning_rate=0.1, random_state=42, n_jobs=-1)
xgb_model.fit(X_train_xgb, y_train)
xgb_pred = xgb_model.predict(X_test_xgb)

xgb_mae = mean_absolute_error(y_test, xgb_pred)
xgb_rmse = np.sqrt(mean_squared_error(y_test, xgb_pred))
xgb_r2 = r2_score(y_test, xgb_pred)

print(f"XGB Results -> R2: {xgb_r2:.4f} | MAE: {xgb_mae:.4f} L/hr | RMSE: {xgb_rmse:.4f} L/hr")

# ============================================================
# 3. SAVE THE BEST MODEL
# ============================================================
if xgb_r2 > rf_r2:
    print("\nXGBoost performed better. Saving XGBoost model as fuel_model.pkl")
    joblib.dump(xgb_model, "fuel_model.pkl")
else:
    print("\nRandom Forest performed better. Saving Random Forest model as fuel_model.pkl")
    joblib.dump(rf_model, "fuel_model.pkl")