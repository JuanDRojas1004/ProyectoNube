import os
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Key
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pymongo import MongoClient


app = FastAPI(title="IoT Sensors API")

DYNAMO_TABLE = os.getenv("DYNAMO_TABLE", "SensorData-lab")
MONGO_URI = os.getenv("MONGO_URI", "mongodb://3.88.194.185:27017/iot_history")

dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
table = dynamodb.Table(DYNAMO_TABLE)

mongo_client = MongoClient(MONGO_URI)
mongo_db = mongo_client["iot_history"]
mongo_collection = mongo_db["sensor_events"]


class Sensor(BaseModel):
    device_id: str
    sensor_type: str


def clean_item(item):
    clean = {}

    for key, value in item.items():
        if isinstance(value, Decimal):
            if value % 1 == 0:
                clean[key] = int(value)
            else:
                clean[key] = float(value)
        else:
            clean[key] = value

    return clean


@app.get("/sensors")
def get_sensors():
    response = table.scan()
    items = response.get("Items", [])

    sensors = {}

    for item in items:
        device_id = item.get("device_id")

        if device_id:
            sensors[device_id] = {
                "device_id": device_id,
                "sensor_type": item.get("sensor_type")
            }

    return list(sensors.values())


@app.post("/sensors")
def post_sensor(sensor: Sensor):
    item = {
        "device_id": sensor.device_id,
        "timestamp": "REGISTERED",
        "sensor_type": sensor.sensor_type,
        "value": 0
    }

    table.put_item(Item=item)

    return {
        "message": "Sensor agregado correctamente",
        "sensor": item
    }


@app.get("/sensor/{sensor_id}/current")
def get_current(sensor_id: str):
    response = table.query(
        KeyConditionExpression=Key("device_id").eq(sensor_id),
        ScanIndexForward=False,
        Limit=1
    )

    items = response.get("Items", [])

    if not items:
        raise HTTPException(status_code=404, detail="Sensor no encontrado")

    return clean_item(items[0])


@app.get("/sensor/{sensor_id}/recent")
def get_recent(sensor_id: str):
    response = table.query(
        KeyConditionExpression=Key("device_id").eq(sensor_id),
        ScanIndexForward=False,
        Limit=10
    )

    items = response.get("Items", [])

    return [clean_item(item) for item in items]


@app.get("/sensor/{sensor_id}/history")
def get_history(sensor_id: str):
    documents = mongo_collection.find(
        {"device_id": sensor_id},
        {"_id": 0}
    ).sort("timestamp", -1)

    return list(documents)