#!/usr/bin/env python3
"""ULTIMATE DEBUGGING SCRIPT for Synapse PostgreSQL issue"""
import sys
import os

# Flush immediately
sys.stdout = os.fdopen(sys.stdout.fileno(), 'w', buffering=1)
sys.stderr = os.fdopen(sys.stderr.fileno(), 'w', buffering=1)

# Write to a debug file directly
DEBUG_LOG = '/data/synapse_debug.log'

def dlog(msg):
    timestamp = __import__('datetime').datetime.now().isoformat()
    line = f'[{timestamp}] ULTIMATE DEBUG: {msg}\n'
    sys.stderr.write(line)
    sys.stderr.flush()
    try:
        with open(DEBUG_LOG, 'a') as f:
            f.write(line)
    except:
        pass

dlog('===== STARTING ULTIMATE DEBUG =====')

# Patch BOTH system psycopg2 AND synapse's bundled copy
dlog('Patching psycopg2 module...')
import psycopg2
_original_connect = psycopg2.connect

# ALSO patch synapse's bundled copy if it exists
try:
    import synapse.storage.database
    if hasattr(synapse.storage.database, 'psycopg2'):
        dlog(' ALSO patching synapse.storage.database.psycopg2')
        synapse.storage.database.psycopg2.connect = debug_connect
    else:
        dlog('synapse.storage.database.psycopg2 not found, will try later patch')
except Exception as e:
    dlog(f'Could not check synapse database: {e}')

def debug_connect(dsn=None, connection_factory=None, cursor_factory=None, is_async=False, **kwargs):
    dlog(f'psycopg2.connect CALLED! dsn={type(dsn)}')
    if isinstance(dsn, dict):
        dlog(f'  dsn: {dsn}')
    else:
        dlog(f'  dsn: {str(dsn)[:100]}')
    sys.stderr.flush()
    
    try:
        result = _original_connect(dsn, connection_factory, cursor_factory, is_async, **kwargs)
        dlog('psycopg2.connect SUCCEEDED!')
        return result
    except Exception as e:
        dlog(f'psycopg2.connect FAILED: {e}')
        sys.stderr.flush()
        raise

psycopg2.connect = debug_connect
dlog('psycopg2 patched!')

# Patch asyncpg - CRITICAL for Twisted!
dlog('Patching asyncpg module (CRITICAL!)...')
try:
    import asyncpg
    _orig_asyncpg = asyncpg.connect
    
    async def debug_asyncpg(dsn, *args, **kwargs):
        dlog(f'!!! asyncpg.connect CALLED !!! dsn={dsn}')
        sys.stderr.flush()
        try:
            result = await _orig_asyncpg(dsn, *args, **kwargs)
            dlog('!!! asyncpg.connect SUCCEEDED !!!')
            sys.stderr.flush()
            return result
        except Exception as e:
            dlog(f'!!! asyncpg.connect FAILED !!!: {e}')
            sys.stderr.flush()
            raise
    
    asyncpg.connect = debug_asyncpg
    dlog('asyncpg patched!')
except Exception as e:
    dlog(f'asyncpg patch failed: {e}')

# Patch Twisted reactor - this is where the hang likely is!
dlog('Patching Twisted reactor...')
try:
    from twisted.internet import reactor
    
    _orig_listen = reactor.listenTCP
    _orig_connect = reactor.connectTCP
    
    def debug_listen(port, factory, *a, **kw):
        dlog(f'!!! reactor.listenTCP({port}, ...) CALLED !!!')
        sys.stderr.flush()
        result = _orig_listen(port, factory, *a, **kw)
        dlog(f'!!! reactor.listenTCP({port}) SUCCEEDED !!!')
        return result
    
    def debug_connect(host, port, factory, *a, **kw):
        dlog(f'!!! reactor.connectTCP({host}:{port}) CALLED !!!')
        sys.stderr.flush()
        result = _orig_connect(host, port, factory, *a, **kw)
        dlog(f'!!! reactor.connectTCP SUCCEEDED !!!')
        return result
    
    reactor.listenTCP = debug_listen
    reactor.connectTCP = debug_connect
    dlog('Twisted reactor patched!')
except Exception as e:
    dlog(f'Twisted patch failed: {e}')

dlog('===== RUNNING SYNAPSE =====')
sys.stderr.flush()

# Run synapse via exec
os.execv(sys.executable, [sys.executable, '-m', 'synapse.app.homeserver', '--config-path', '/data/homeserver.yaml'])