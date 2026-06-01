import json


def lambda_handler(event, context):
    for record in event.get("Records", []):
        body = json.loads(record["body"])

        print("=== ALERTA DE URGENCIA ===")
        print(json.dumps(body, indent=2))
        print("==========================")

    return {
        "statusCode": 200,
        "body": json.dumps("Alertas registradas en CloudWatch")
    }