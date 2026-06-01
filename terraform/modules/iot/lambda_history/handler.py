import json
import os
from urllib.parse import unquote_plus

import boto3
from pymongo import MongoClient


s3_client = boto3.client("s3")


def lambda_handler(event, context):
    mongo_uri = os.environ["MONGODB_URI"]

    client = MongoClient(mongo_uri)
    database = client["iot_history"]
    collection = database["sensor_events"]

    for record in event.get("Records", []):
        bucket_name = record["s3"]["bucket"]["name"]
        object_key = unquote_plus(record["s3"]["object"]["key"])

        print(f"Leyendo archivo S3: bucket={bucket_name}, key={object_key}")

        response = s3_client.get_object(
            Bucket=bucket_name,
            Key=object_key
        )

        body = response["Body"].read().decode("utf-8")
        sensor_event = json.loads(body)

        sensor_event["s3_bucket"] = bucket_name
        sensor_event["s3_key"] = object_key

        collection.insert_one(sensor_event)

        print(f"Evento guardado en MongoDB: {sensor_event}")

    return {
        "statusCode": 200,
        "body": "Eventos procesados correctamente"
    }