import json
import os

import boto3
import pymysql

_creds = None


def _load(refresh=False):
    """Read the RDS-managed master secret from Secrets Manager (cached per process)."""
    global _creds
    if _creds is None or refresh:
        sm = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
        secret = sm.get_secret_value(SecretId=os.environ["DB_SECRET_ARN"])
        _creds = json.loads(secret["SecretString"])
    return _creds


def _connect(c):
    return pymysql.connect(
        host=os.environ["DB_HOST"],
        user=c["username"],
        password=c["password"],
        database=os.environ["DB_NAME"],
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        connect_timeout=5,
    )


def get_conn():
    try:
        return _connect(_load())
    except pymysql.err.OperationalError as e:
        # 1045 = access denied: the managed password was rotated, so fetch the new one
        if e.args and e.args[0] == 1045:
            return _connect(_load(refresh=True))
        raise
