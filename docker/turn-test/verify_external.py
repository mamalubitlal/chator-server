import socket, time, urllib.request, sys, json

import os
HOST = os.environ.get("TARGET_HOST", "178.166.228.93")
PORT = int(os.environ.get("TARGET_PORT", "3478"))
magicCookie = bytes([0x21, 0x12, 0xA4, 0x42])
txId = bytes(range(12))
msg = bytes([0x00, 0x01, 0x00, 0x00]) + magicCookie + txId

print("=== STUN UDP Test ===")
print(f"Target: {HOST}:{PORT}")
print()

for i in range(3):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(5)
    t1 = time.time()
    s.sendto(msg, (HOST, PORT))
    try:
        data, addr = s.recvfrom(512)
        dt = time.time() - t1
        off = 20
        xaddr = "?"
        while off + 4 <= len(data):
            atype = data[off] << 8 | data[off+1]
            alen = data[off+2] << 8 | data[off+3]
            if atype == 0x0020 and alen >= 8:
                family = data[off+5]
                if family == 1:
                    xport = (data[off+6] << 8 | data[off+7]) ^ 0x2112
                    xip = ".".join(str(data[off+8+i] ^ magicCookie[i]) for i in range(4))
                    xaddr = f"{xip}:{xport}"
            off += 4 + alen
        print(f"TRY {i+1}: OK [{dt*1000:.0f}ms]  XOR-MAPPED-ADDR: {xaddr}")
    except socket.timeout:
        print(f"TRY {i+1}: TIMEOUT")
    s.close()

print()
print("=== Synapse HTTP Test ===")
for port, name in [(8008, "Client-Server API"), (8448, "Federation proxy")]:
    try:
        r = urllib.request.urlopen(f"http://{HOST}:{port}/_matrix/client/versions", timeout=5)
        d = json.loads(r.read())
        ver_count = len(d["versions"])
        print(f"Port {port} ({name}): OK - {ver_count} API versions")
    except Exception as e:
        print(f"Port {port} ({name}): FAIL - {e}")

print()
print("=== TCP 3478 ===")
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
t1 = time.time()
try:
    s.connect((HOST, 3478))
    dt = time.time() - t1
    s.close()
    print(f"TCP 3478: OPEN [{dt*1000:.0f}ms]")
except Exception as e:
    print(f"TCP 3478: FAIL - {e}")
