import numpy as np
import pandas as pd
import MetaTrader5 as mt
from keras.models import Sequential, load_model
from keras.layers import LSTM, Dense
from keras.callbacks import EarlyStopping, ModelCheckpoint
from sklearn.preprocessing import MinMaxScaler
from datetime import datetime, timedelta
import os
import sys

# Ensure the default encoding is set to UTF-8
sys.stdout.reconfigure(encoding='utf-8')

# Configurations
epoch_count = 100
initial_record_count = 120_000
incremental_record_count = 1_000
prediction_count = 1
symbol = 'GBPUSD'
batch_size = 128
window_size = 72
unit_size = 128
model_name = "trained_model.keras"
latest_file_name = "latest.txt"
prediction_file_name = "prediction.txt"
login = 1234567 # update with your MQ5 account number
password = 'abcdefg' # update with your MQ5 account password
server = 'MetaQuotes-Demo' # update with your MQ5 server
verbose_type = 2 # make it 2 to run as script, otherwise 1 to see loading bar

def validate_mt(message):
    if not mt.last_error()[0]:
        print("MT validation failed:")
        print(mt.last_error())
        quit()
    print(message + ": " + mt.last_error()[1])

def read_latest():
    if os.path.exists(latest_file_name):
        with open(latest_file_name, "r") as f:
            return f.read().strip()
    return ''

def write_latest(data):
    with open(latest_file_name, "w") as f:
        f.write(data)

def write_predictions(min_pred, max_pred):
    with open(prediction_file_name, "w") as f:
        f.write(f"{min_pred},{max_pred}")

def create_sliding_windows(data):
    x, y = [], []
    for i in range(len(data) - window_size):
        x.append(data[i:i+window_size])
        y.append(data[i+window_size])
    return np.array(x), np.array(y)

def predict():
    # Open MT5 platform
    mt.initialize(login=login, server=server, password=password)
    validate_mt("Opening MT5")

    mt.login(login, password, server)
    validate_mt("Logining to MT5")

    is_first_run = read_latest() == ''

    rates = mt.copy_rates_from(symbol, mt.TIMEFRAME_H1, datetime.now(), initial_record_count if is_first_run else incremental_record_count)
    validate_mt("Fetching the historical data")

    print(f"Fetched {len(rates)} data properly!")

    data = pd.DataFrame(rates, columns=['time', 'open'])
    data.rename(columns={'time': 'DateTime', 'open': 'Price'}, inplace=True)
    data['DateTime'] = pd.to_datetime(data['DateTime'], unit='s')
    data['Price'] = pd.to_numeric(data['Price'])

    # Sort data by DateTime
    data.sort_values(by='DateTime', inplace=True)

    if not is_first_run:
        latest_proceeded_date = read_latest()
        new_data_count = data[data['DateTime'] > datetime.fromisoformat(latest_proceeded_date)].shape[0]
        data = data.tail(new_data_count + window_size)

    # Extract 'Price' values and normalize
    price_data = data['Price'].values.reshape(-1, 1)
    scaler = MinMaxScaler(feature_range=(0, 1))
    price_data_scaled = scaler.fit_transform(price_data)

    # Generate sliding windows
    x, y = create_sliding_windows(price_data_scaled)

    if not x.any():
        print("No data to train")
        return

    # Build or load LSTM model
    if is_first_run:
        model = Sequential()
        model.add(LSTM(units=unit_size, return_sequences=True, input_shape=(window_size, 1)))
        model.add(LSTM(units=unit_size))
        model.add(Dense(units=prediction_count))
        model.compile(optimizer='adam', loss='mean_squared_error')
    else:
        model = load_model(model_name)

    # Early stopping and model checkpoint
    early_stopping = EarlyStopping(monitor='val_loss', patience=10, restore_best_weights=True)
    model_checkpoint = ModelCheckpoint(model_name, monitor='val_loss', save_best_only=True)

    # Train the model
    model.fit(x, y, epochs=epoch_count, batch_size=batch_size, verbose=verbose_type, callbacks=[early_stopping, model_checkpoint])

    model.save(model_name)

    write_latest(str(max(data['DateTime'].values)))

    # Forecast the next period
    input_data = price_data_scaled[-window_size:].reshape(1, window_size, 1)
    predicted_price_scaled = model.predict(input_data, verbose=verbose_type)
    future_predictions = scaler.inverse_transform(predicted_price_scaled)

    min_prediction = str(np.min(future_predictions))
    max_prediction = str(np.max(future_predictions))
    write_predictions(min_prediction, max_prediction)

predict()
