#!/usr/bin/env python3
import hmac, hashlib, base64, time

secret = "chator-test-secret"
expiry = int(time.time()) + 86400
username = f"{expiry}:chator_test"
digest = hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()
password = base64.b64encode(digest).decode()

print(f"TURN server:  localhost:3478")
print(f"Username:     {username}")
print(f"Password:     {password}")
print(f"Expires:      {time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(expiry))}")
print()
print(f"Test:  turnutils_uclient -u '{username}' -w '{password}' localhost")
