## 2026-05-29 — Fix refresh_tokens + integrate into deploy scripts

**Goal:** Create fix for missing `public.refresh_tokens` table in Synapse's Supabase DB and integrate into deployment workflow.

**Context:** During MAS integration, discovered `refresh_tokens` table is missing from Synapse's database on Supabase pooler. The DB was fully reset (tables dropped for `server_name` change from `localhost` → `chator.duckdns.org`) but `schema_version` table was preserved, so Synapse thinks the schema is complete at version 94 and won't re-apply the full schema — leaving `refresh_tokens` and potentially other objects missing.

**Root cause confirmed:** `RegistrationStore.__init__()` at `synapse/storage/databases/main/registration.py:2684` unconditionally creates `IdGenerator(db_conn, "refresh_tokens", "id")`, which will crash Synapse on startup if the table doesn't exist.

**Approach:**
- Traced Synapse schema init code: `full_schemas/72/full.sql.postgres` INCLUDES `refresh_tokens` table (confirmed). Deltas 73-94 are applied on top, but the full schema was never re-run after the reset.
- Created `deploy/fix-refresh-tokens.py` — standalone script that:
  - Checks if `refresh_tokens` exists, its columns, constraints, indexes
  - Creates the table from `full_schemas/72` definition if missing (includes `expiry_ts`, `ultimate_session_expiry_ts`, `next_token_id`)
  - Adds missing columns to `access_tokens` (`refresh_token_id`, `used`)
  - Adds FK constraints and indexes
  - Registers delta records in `applied_schema_deltas` for tracking
  - Safe to run multiple times (idempotent)
- Created `deploy/fix-synapse-db.sh` — simple root wrapper
- Updated `deploy/finalize.sh` — runs fix as step 0 (before MAS config patching, before service restart)
- Updated `deploy/install-mas.sh` — runs fix in `--migrate` section before stopping Synapse

**Files created:**
- `deploy/fix-refresh-tokens.py` — main fix script (standalone, no local file deps)
- `deploy/fix-synapse-db.sh` — quick wrapper

**Files modified:**
- `deploy/finalize.sh` — step 0: fix DB schema
- `deploy/install-mas.sh` — fix DB before migration

**Key decisions:**
- Created the table manually (from full_schema definition) rather than dropping/recreating the whole DB
- Registered delta records in `applied_schema_deltas` so Synapse's migration tracker stays consistent
- Integrated into existing deploy scripts rather than creating a separate manual step

**Next after this:** User copies repo to VPS, runs `fix-synapse-db.sh` (or `finalize.sh`), restarts Synapse, verifies startup. Then proceed with MAS migration (`install-mas.sh --migrate`).

**Status:** ready for deployment

<blank line>
<blank line>
## 2026-05-29 — Synapse Database Schema Initialization Analysis

**Goal:** Understand how Synapse initializes database schema on first startup, specifically how it selects full_schemas, tracks applied deltas, and handles post-install delta application.

**Approach:** Examined prepare_database.py, schema_version.sql, and schema directory structure to trace the initialization logic.

**Key findings:**

1. **Full schema selection:** In `_setup_new_database()` function, Synapse:
   - Scans `schema/common/full_schemas/` for version directories
   - Selects the highest version number ≤ `SCHEMA_VERSION` (currently 94)
   - Executes all .sql files in that version's directory from both common and database-specific locations
   - For a fresh install, this would use full_schemas/72/ (the highest available)

2. **Delta tracking:** The `applied_schema_deltas` table (created in schema_version.sql) tracks:
   - `version`: schema version the delta belongs to
   - `file`: relative path of the delta file
   - Has UNIQUE constraint on (version, file) to prevent duplicate application
   - Populated in `_upgrade_existing_database()` after each delta is applied

3. **Post-install delta application:** Yes, after installing full_schema/72:
   - `_setup_new_database()` calls `_upgrade_existing_database()` with `is_empty=True`
   - This applies all deltas from version 73 through current SCHEMA_VERSION (94)
   - The logic in `_upgrade_existing_database()` skips deltas for the base version if `upgraded=False` (indicating full schema was used)
   - Then iterates from `start_ver` (base_version+1) to `SCHEMA_VERSION`, applying all deltas

**Files created/modified:** None (analysis only)
**Status:** done