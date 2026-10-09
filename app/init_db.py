import os
import time

from dbconfig import get_conn

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")
statements = [s.strip() for s in open(path).read().split(";") if s.strip()]

for attempt in range(10):
    try:
        conn = get_conn()
        with conn.cursor() as c:
            for stmt in statements:
                c.execute(stmt)
        conn.commit()
        conn.close()
        print("schema ready")
        break
    except Exception as e:  # DB or secret not ready yet, or another instance is creating the tables
        print("init attempt", attempt, e)
        time.sleep(10)
else:
    raise SystemExit(1)
