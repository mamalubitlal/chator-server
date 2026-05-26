#!/bin/bash
# Test STUN UDP from external network
HOST="${TARGET_HOST:-localhost}"
PORT=3478
RETRIES=5

echo "Testing STUN UDP to $HOST:$PORT"
echo "---"

for i in $(seq 1 $RETRIES); do
  python3 -c "
import socket, time, sys
magicCookie = bytes([0x21, 0x12, 0xA4, 0x42])
txId = bytes([1,2,3,4,5,6,7,8,9,10,11,12])
msg = bytes([0x00, 0x01, 0x00, 0x00]) + magicCookie + txId

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(3)
t1 = time.time()
s.sendto(msg, ('$HOST', $PORT))
try:
    data, addr = s.recvfrom(512)
    dt = time.time() - t1
    print(f'TRY $i: OK from {addr[0]}:{addr[1]} in {dt*1000:.0f}ms')
    s.close()
    sys.exit(0)
except socket.timeout:
    print(f'TRY $i: TIMEOUT')
s.close()
time.sleep(0.5)
"
done

echo "---"
echo "UDP STUN test FAILED after $RETRIES attempts"

# Also test TCP connectivity for comparison
echo ""
echo "TCP test for comparison:"
timeout 3 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null && echo "TCP $PORT: OPEN" || echo "TCP $PORT: closed"
