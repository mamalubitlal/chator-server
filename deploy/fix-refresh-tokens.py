#!/usr/bin/env python3
"""
Fix missing refresh_tokens table and schema gaps in Synapse's PostgreSQL database.

The full_schema/72 includes refresh_tokens, but a prior DB reset
(dropping all tables for server_name change) preserved schema_version.
Synapse thinks the DB is complete at version 94, so it won't re-apply
the full schema — leaving refresh_tokens and potentially other objects missing.

Usage:
  ./fix-refresh-tokens.py              # uses env vars or defaults
  PGPASSWORD="..." ./fix-refresh-tokens.py

Safe to run multiple times — uses IF NOT EXISTS / IF NOT FOUND guards.
"""

import os
import sys

import psycopg2
from psycopg2 import sql

# ── Config (overridable via env) ────────────────────────────────────────────
DB_USER = os.environ.get("PGUSER", "postgres.ukymrxkunsylwiagdowy")
DB_PASS = os.environ.get("PGPASSWORD", "do4ePaNXnyiD7xkX")
DB_NAME = os.environ.get("PGDATABASE", "postgres")
DB_HOST = os.environ.get("PGHOST", "aws-1-eu-central-1.pooler.supabase.com")
DB_PORT = int(os.environ.get("PGPORT", "5432"))
DB_SSLMODE = os.environ.get("PGSSLMODE", "require")

# ── Schema SQL ──────────────────────────────────────────────────────────────

CREATE_REFRESH_TOKENS = """
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id bigint NOT NULL,
    user_id text NOT NULL,
    device_id text NOT NULL,
    token text NOT NULL,
    next_token_id bigint,
    expiry_ts bigint,
    ultimate_session_expiry_ts bigint
);
"""

REFRESH_TOKENS_PK = """
ALTER TABLE refresh_tokens ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);
"""

REFRESH_TOKENS_TOKEN_UNIQUE = """
ALTER TABLE refresh_tokens ADD CONSTRAINT refresh_tokens_token_key UNIQUE (token);
"""

REFRESH_TOKENS_SELF_FK = """
ALTER TABLE refresh_tokens ADD CONSTRAINT refresh_tokens_next_token_id_fkey
    FOREIGN KEY (next_token_id) REFERENCES refresh_tokens(id) ON DELETE CASCADE;
"""

REFRESH_TOKENS_NEXT_TOKEN_ID_IDX = """
CREATE INDEX IF NOT EXISTS refresh_tokens_next_token_id
    ON refresh_tokens(next_token_id)
    WHERE next_token_id IS NOT NULL;
"""

ACCESS_TOKENS_FK = """
ALTER TABLE access_tokens ADD CONSTRAINT access_tokens_refresh_token_id_fkey
    FOREIGN KEY (refresh_token_id) REFERENCES refresh_tokens(id) ON DELETE CASCADE;
"""

# ── Connection ──────────────────────────────────────────────────────────────

def connect():
    conn = psycopg2.connect(
        user=DB_USER, password=DB_PASS, dbname=DB_NAME,
        host=DB_HOST, port=DB_PORT, sslmode=DB_SSLMODE,
    )
    conn.set_session(autocommit=True)
    return conn


# ── Introspection helpers ───────────────────────────────────────────────────

def table_exists(cur, schema, table):
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_tables "
        "WHERE schemaname=%s AND tablename=%s)", (schema, table))
    return cur.fetchone()[0]


def column_exists(cur, schema, table, column):
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute "
        "WHERE attrelid=%s::regclass AND attname=%s AND NOT attisdropped)",
        (f"{schema}.{table}", column))
    return cur.fetchone()[0]


def column_type(cur, schema, table, column):
    cur.execute(
        "SELECT pg_catalog.format_type(atttypid, atttypmod) "
        "FROM pg_catalog.pg_attribute "
        "WHERE attrelid=%s::regclass AND attname=%s AND NOT attisdropped",
        (f"{schema}.{table}", column))
    r = cur.fetchone()
    return r[0] if r else None


def constraint_exists(cur, schema, table, conname):
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint "
        "WHERE conrelid=%s::regclass AND conname=%s)",
        (f"{schema}.{table}", conname))
    return cur.fetchone()[0]


def index_exists(cur, schema, idxname):
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_indexes "
        "WHERE schemaname=%s AND indexname=%s)", (schema, idxname))
    return cur.fetchone()[0]


def register_delta(cur, version, filename):
    cur.execute(
        "INSERT INTO applied_schema_deltas (version, file) VALUES (%s, %s) "
        "ON CONFLICT (version, file) DO NOTHING",
        (version, filename))


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("Synapse schema repair — refresh_tokens & friends")
    print("=" * 60)

    conn = connect()
    cur = conn.cursor()

    # ── 1. Schema version state ─────────────────────────────────────────────
    print("\n--- Schema version state ---")
    try:
        cur.execute("SELECT version, upgraded FROM schema_version")
        v, upgraded = cur.fetchone()
        print(f"  schema_version: v={v}, upgraded={upgraded}")
    except psycopg2.Error as e:
        print(f"  ERROR: {e}")
        print("  (schema_version table missing — not a Synapse DB?)")
        sys.exit(1)

    try:
        cur.execute("SELECT compat_version FROM schema_compat_version")
        cv = cur.fetchone()[0]
        print(f"  schema_compat_version: {cv}")
    except psycopg2.Error:
        print("  schema_compat_version: <not found>")

    cur.execute("SELECT COUNT(*) FROM applied_schema_deltas")
    print(f"  applied_schema_deltas count: {cur.fetchone()[0]}")

    cur.execute(
        "SELECT version, file FROM applied_schema_deltas WHERE file LIKE '%%refresh%%' ORDER BY version")
    rows = cur.fetchall()
    if rows:
        print("  Existing refresh-related deltas registered:")
        for dv, fn in rows:
            print(f"    v{dv}: {fn}")
    else:
        print("  No refresh-related deltas registered (expected for full-schema install)")

    # ── 2. refresh_tokens table ─────────────────────────────────────────────
    print("\n--- refresh_tokens table ---")
    if table_exists(cur, "public", "refresh_tokens"):
        print("  EXISTS")
        for col, typ in [("id", "bigint"), ("user_id", "text"), ("device_id", "text"),
                          ("token", "text"), ("next_token_id", "bigint"),
                          ("expiry_ts", "bigint"), ("ultimate_session_expiry_ts", "bigint")]:
            actual = column_type(cur, "public", "refresh_tokens", col)
            ok = actual == typ
            print(f"  {'✓' if ok else '✗'} {col}  {actual or '<MISSING>'}{'' if ok else f' (expected {typ})'}")

        for con in ["refresh_tokens_pkey", "refresh_tokens_token_key",
                     "refresh_tokens_next_token_id_fkey"]:
            print(f"  {'✓' if constraint_exists(cur,'public','refresh_tokens',con) else '✗'} constraint {con}")

        print(f"  {'✓' if index_exists(cur,'public','refresh_tokens_next_token_id') else '✗'} index refresh_tokens_next_token_id")
    else:
        print("  MISSING — creating...")
        cur.execute(CREATE_REFRESH_TOKENS)
        print("  ✓ table created")

        for label, stmt in [
            ("PRIMARY KEY", REFRESH_TOKENS_PK),
            ("UNIQUE(token)", REFRESH_TOKENS_TOKEN_UNIQUE),
            ("self-referencing FK", REFRESH_TOKENS_SELF_FK),
        ]:
            try:
                cur.execute(stmt)
                print(f"  ✓ {label}")
            except psycopg2.Error as e:
                if "already exists" in str(e).lower():
                    print(f"  ✓ {label} (already exists)")
                else:
                    print(f"  ⚠ {label}: {e}")

        cur.execute(REFRESH_TOKENS_NEXT_TOKEN_ID_IDX)
        print("  ✓ index created")

        # Register deltas so migration tracking is consistent
        register_delta(cur, 59, "14refresh_tokens.sql")
        register_delta(cur, 65, "10_expirable_refresh_tokens.sql")
        register_delta(cur, 68, "04_refresh_tokens_index_next_token_id.sql")
        print("  ✓ delta records inserted into applied_schema_deltas")

    # ── 3. access_tokens columns ────────────────────────────────────────────
    print("\n--- access_tokens columns ---")
    if not table_exists(cur, "public", "access_tokens"):
        print("  ERROR: access_tokens table not found — cannot proceed")
        sys.exit(1)

    for col, typ in [("refresh_token_id", "bigint"), ("used", "boolean")]:
        if column_exists(cur, "public", "access_tokens", col):
            actual = column_type(cur, "public", "access_tokens", col)
            ok = actual == typ
            print(f"  {'✓' if ok else '⚠'} {col} = {actual}" +
                  (f" (expected {typ})" if not ok else ""))
        else:
            print(f"  ✗ {col} MISSING — adding...")
            try:
                cur.execute(
                    sql.SQL("ALTER TABLE access_tokens ADD COLUMN {} {}").format(
                        sql.Identifier(col), sql.SQL(typ)))
                print(f"  ✓ {col} added")
            except psycopg2.Error as e:
                print(f"  ⚠ {e}")

    if not constraint_exists(cur, "public", "access_tokens",
                              "access_tokens_refresh_token_id_fkey"):
        print("  ✗ FK access_tokens → refresh_tokens MISSING — adding...")
        try:
            cur.execute(ACCESS_TOKENS_FK)
            print("  ✓ FK added")
        except psycopg2.Error as e:
            print(f"  ⚠ {e}")
    else:
        print("  ✓ FK access_tokens → refresh_tokens exists")

    # ── 4. Summary ──────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    refresh_ok = table_exists(cur, "public", "refresh_tokens")
    at_cols_ok = (column_exists(cur, "public", "access_tokens", "refresh_token_id") and
                  column_exists(cur, "public", "access_tokens", "used"))

    print(f"  refresh_tokens table:    {'✓ OK' if refresh_ok else '✗ STILL MISSING'}")
    print(f"  access_tokens columns:   {'✓ OK' if at_cols_ok else '⚠ check above'}")

    cur.execute("SELECT COUNT(*) FROM applied_schema_deltas")
    print(f"  Total applied deltas:    {cur.fetchone()[0]}")
    print()

    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
