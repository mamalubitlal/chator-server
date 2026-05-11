#!/usr/bin/env python3
import psycopg2

conn = psycopg2.connect(
    host='fdqjxkzvuiksvxhtcshs.db.eu-central-1.nhost.run',
    port=5432,
    user='postgres',
    password='!Fuckyouroskomnadzor2014',
    database='fdqjxkzvuiksvxhtcshs',
    sslmode='disable'
)
cur = conn.cursor()
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name")
tables = cur.fetchall()
print(f'Tables: {len(tables)}')
for t in tables:
    print(f'  {t[0]}')
cur.close()
conn.close()