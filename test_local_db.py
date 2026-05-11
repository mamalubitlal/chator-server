#!/usr/bin/env python3
import psycopg2
import os
import os.path

# Try common passwords from common paths
passwords = ['postgres', os.environ.get('PGPASSWORD', '')]
credentials = [
    ('postgres', 'postgres', 'postgres'),
    ('postgres', 'postgres', 'chator'),
    ('postgres', 'postgres', 'chator_synapse'),
]

user = os.environ.get('PGUSER', 'postgres')
pw = os.environ.get('PGPASSWORD', 'postgres')
db = os.environ.get('PGDATABASE', 'postgres')

try:
    conn = psycopg2.connect(
        host='host.docker.internal',
        port=5432,
        user=user,
        password=pw,
        database=db,
        sslmode='disable',
        connect_timeout=5
    )
    print(f'{db}: OK, version={conn.server_version}')
    cur = conn.cursor()
    cur.execute('SELECT current_database()')
    print('Database:', cur.fetchone())
    conn.close()
except Exception as e:
    print(f'{db}: {e}')