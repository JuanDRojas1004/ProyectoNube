import json
import os
import boto3


sqs_client = boto3.client("sqs")


def lambda_handler(event, context):
    queue_url = os.environ["ALERT_QUEUE_URL"]

    message = {
        "alert_type": "HIGH_TEMPERATURE",
        "device_id": event.get("device_id"),
        "sensor_type": event.get("sensor_type"),
        "value": event.get("value"),
        "timestamp": event.get("timestamp"),
        "message": "Temperatura critica detectada"
    }

    sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(message)
    )

    print(f"Alerta enviada a SQS: {message}")

    return {
        "statusCode": 200,
        "body": json.dumps("Alerta procesada")
    }