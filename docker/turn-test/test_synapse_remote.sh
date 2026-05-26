#!/bin/bash
HOST="${TARGET_HOST:-178.166.228.93}"

echo '=== 1. Port 8008 — Client-Server API ==='

echo -n '   versions: '
curl -s -m 10 http://$HOST:8008/_matrix/client/versions | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"{len(d["versions"])} versions")' 2>/dev/null || echo 'FAIL'

echo -n '   health:   '
curl -s -m 10 http://$HOST:8008/health 2>/dev/null || echo 'FAIL'

echo -n '   whoami:   '
curl -s -m 10 http://$HOST:8008/_matrix/client/v1/whoami -X POST -H 'Content-Type: application/json' -d '{}' 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"errcode={d.get(\"errcode\",\"none\")}")' 2>/dev/null || echo 'FAIL (expected — no token)'

echo ''
echo '=== 2. Port 8448 — Federation port (proxied to 8008) ==='

echo -n '   versions: '
curl -s -m 10 http://$HOST:8448/_matrix/client/versions | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"{len(d["versions"])} versions")' 2>/dev/null || echo 'FAIL'

echo -n '   health:   '
curl -s -m 10 http://$HOST:8448/health 2>/dev/null || echo 'FAIL'

echo ''
echo '=== 3. Matrix well-known discovery ==='

echo -n '   .well-known/matrix/server: '
curl -s -m 10 http://$HOST:8008/.well-known/matrix/server 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(str(d))' 2>/dev/null || echo '(not configured — ok)'

echo -n '   .well-known/matrix/client: '
curl -s -m 10 http://$HOST:8008/.well-known/matrix/client 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(str(d))' 2>/dev/null || echo '(not configured — ok)'

echo ''
echo '=== 4. TURN/STUN ==='

echo -n '   TCP 3478: '
timeout 3 bash -c 'echo > /dev/tcp/'$HOST'/3478' 2>/dev/null && echo 'OPEN' || echo 'closed'

echo -n '   STUN UDP 3478: '
python3 -c "
import socket, struct, time
msg = bytes.fromhex('000100582112a442d7c87f224d7ed0e9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000')
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(5)
t1 = time.time()
s.sendto(msg, ('$HOST', 3478))
try:
    data, addr = s.recvfrom(512)
    dt = time.time() - t1
    print(f'STUN response from {addr[0]}:{addr[1]} in {dt*1000:.0f}ms')
except socket.timeout:
    print('TIMEOUT (UDP blocked)')
s.close()
" 2>&1

echo ''
echo '=== Done ==='
