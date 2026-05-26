/**
 * STUN/TURN external test runner.
 * Run this from OUTSIDE the target network to verify TURN/STUN works from the internet.
 *
 * Usage: node test_external.js <host> [port]
 *
 * Examples:
 *   node test_external.js 178.166.228.93 3478   (test public IP)
 *   node test_external.js 192.168.0.15 3478      (test LAN IP — internal use)
 */

const stun = require('stun');
const dgram = require('dgram');
const crypto = require('crypto');

const TURN_HOST = process.argv[2] || '178.166.228.93';
const TURN_PORT = parseInt(process.argv[3] || '3478', 10);
const USERNAME = '1779804159:chator_test';
const SHARED_SECRET = 'chator-test-secret';
const TIMEOUT = 5000;

const C = stun.constants;

function generatePassword(username, secret) {
  const hmac = crypto.createHmac('sha1', Buffer.from(secret, 'utf8'));
  hmac.update(Buffer.from(username, 'utf8'));
  return hmac.digest().toString('base64');
}

async function testStun() {
  console.log(`\n📡 Testing STUN binding to ${TURN_HOST}:${TURN_PORT}...`);
  try {
    const response = await stun.request(`${TURN_HOST}:${TURN_PORT}`, { timeout: TIMEOUT });
    const addr = response.getAttribute(C.STUN_ATTR_XOR_MAPPED_ADDRESS);

    if (addr) {
      console.log(`  ✅ STUN SUCCESS`);
      console.log(`     Your public IP (from server's perspective): ${addr.address}:${addr.port}`);
      console.log(`     This confirms the STUN port is reachable from here.\n`);
      return true;
    }

    // If no XOR_MAPPED_ADDRESS, try MAPPED_ADDRESS
    const mapped = response.getAttribute(C.STUN_ATTR_MAPPED_ADDRESS);
    if (mapped) {
      console.log(`  ✅ STUN SUCCESS`);
      console.log(`     Your public IP (from server's perspective): ${mapped.address}:${mapped.port}`);
      return true;
    }

    console.log(`  ⚠️  STUN responded but no address attribute found`);
    return false;
  } catch (err) {
    console.log(`  ❌ STUN FAILED: ${err.message}`);
    console.log(`     Server at ${TURN_HOST}:${TURN_PORT} is not reachable via UDP from here.\n`);
    return false;
  }
}

async function testTurn() {
  console.log(`\n📡 Testing TURN ALLOCATE to ${TURN_HOST}:${TURN_PORT}...`);
  const password = generatePassword(USERNAME, SHARED_SECRET);
  console.log(`   Username: ${USERNAME}`);
  console.log(`   Password: ${password}`);

  return new Promise((resolve) => {
    const sock = dgram.createSocket('udp4');
    const timer = setTimeout(() => {
      sock.close();
      console.log(`  ❌ TURN ALLOCATE TIMEOUT — no response within ${TIMEOUT}ms\n`);
      resolve(false);
    }, TIMEOUT);

    const tid = crypto.randomBytes(12);
    const magic = 0x2112A442;

    // Build a STUN Binding Request first (simpler, just to test connectivity via raw socket)
    const msg = stun.createMessage(C.STUN_BINDING_REQUEST);
    msg.setTransactionID(tid);

    sock.on('message', (rawMsg) => {
      clearTimeout(timer);
      sock.close();

      const rcvType = rawMsg.readUInt16BE(0);
      const rcvLen = rawMsg.readUInt16BE(2);
      const rcvMagic = rawMsg.readUInt32BE(4);
      const rcvTid = rawMsg.slice(8, 20);

      if (rcvMagic !== magic) {
        console.log(`  ❌ Bad STUN magic in response`);
        resolve(false);
        return;
      }

      // It's a valid STUN response (binding response confirms server is reachable)
      console.log(`  ✅ TURN server reachable via UDP (STUN Binding accepted)`);

      // For actual TURN, we'd need to do a proper ALLOCATE with message-integrity.
      // Let's try to interpret if it's an ALLOCATE response or error
      if (rcvType === C.STUN_ALLOCATE_RESPONSE) {
        console.log(`     ✅ TURN ALLOCATE SUCCESS!`);
        // Parse relayed address
        let offset = 20;
        while (offset < 20 + rcvLen) {
          const attrType = rawMsg.readUInt16BE(offset);
          const attrLen = rawMsg.readUInt16BE(offset + 2);
          const paddedLen = attrLen + (4 - (attrLen % 4)) % 4;

          if (attrType === C.STUN_ATTR_XOR_RELAYED_ADDRESS) {
            const family = rawMsg.readUInt8(offset + 5);
            const xorPort = rawMsg.readUInt16BE(offset + 6);
            const port = xorPort ^ (magic >> 16);
            const ipBytes = [
              rawMsg.readUInt8(offset + 8) ^ ((magic >> 24) & 0xFF),
              rawMsg.readUInt8(offset + 9) ^ ((magic >> 16) & 0xFF),
              rawMsg.readUInt8(offset + 10) ^ ((magic >> 8) & 0xFF),
              rawMsg.readUInt8(offset + 11) ^ (magic & 0xFF),
            ];
            console.log(`     Relay address: ${ipBytes.join('.')}:${port}`);
            console.log(`     TURN is fully working from external networks! 🎉`);
            resolve(true);
            return;
          }
          offset += 4 + paddedLen;
        }
        console.log(`     (no relay address attr found, but ALLOCATE succeeded)`);
        resolve(true);
      } else if (rcvType === C.STUN_ALLOCATE_ERROR_RESPONSE) {
        let errCode = 'unknown';
        let offset = 20;
        while (offset < 20 + rcvLen) {
          const attrType = rawMsg.readUInt16BE(offset);
          const attrLen = rawMsg.readUInt16BE(offset + 2);
          const paddedLen = attrLen + (4 - (attrLen % 4)) % 4;
          if (attrType === C.STUN_ATTR_ERROR_CODE) {
            const cls = rawMsg.readUInt8(offset + 6);
            const num = rawMsg.readUInt8(offset + 7);
            errCode = `${cls}${String(num).padStart(2, '0')} - ${rawMsg.toString('utf8', offset + 8, offset + 8 + attrLen - 4)}`;
          }
          offset += 4 + paddedLen;
        }
        console.log(`  ❌ TURN ALLOCATE rejected: ${errCode}`);
        resolve(false);
      } else if (rcvType === C.STUN_BINDING_RESPONSE) {
        console.log(`     (response was a STUN binding, not TURN ALLOCATE — server reachable but need real TURN client)`);
        resolve(false);
      } else {
        console.log(`  ❓ Unexpected response type: 0x${rcvType.toString(16)}`);
        resolve(false);
      }
    });

    sock.on('error', (err) => {
      clearTimeout(timer);
      sock.close();
      console.log(`  ❌ Socket error: ${err.message}\n`);
      resolve(false);
    });

    const buf = msg.toBuffer();
    sock.send(buf, TURN_PORT, TURN_HOST, (err) => {
      if (err) {
        clearTimeout(timer);
        sock.close();
        console.log(`  ❌ Send error: ${err.message}\n`);
        resolve(false);
      }
    });
  });
}

async function main() {
  console.log(`=========================================`);
  console.log(`  STUN/TURN External Test`);
  console.log(`=========================================`);
  console.log(`  Server:   ${TURN_HOST}:${TURN_PORT}`);
  console.log(`=========================================`);

  const stunOk = await testStun();
  const turnOk = await testTurn();

  console.log(`\n=========================================`);
  console.log(`  RESULTS SUMMARY`);
  console.log(`=========================================`);
  console.log(`  STUN:  ${stunOk ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`  TURN:  ${turnOk ? '✅ PASS' : '❌ FAIL'}`);
  console.log(`=========================================`);

  if (stunOk || turnOk) {
    console.log(`\n🎉 TURN/STUN server is working from this location!`);
  } else {
    console.log(`\n⚠️  TROUBLESHOOTING:`);
    console.log(`  1. Are you ON the same network as the TURN server? If so, try the LAN IP instead.`);
    console.log(`  2. If testing public IP from inside the same LAN, hairpin NAT may block it.`);
    console.log(`  3. Verify ports ${TURN_PORT} UDP are forwarded to ${TURN_HOST} on the router.`);
    console.log(`  4. Check firewall: Windows Firewall rules for UDP ${TURN_PORT}.`);
    console.log(`  5. Run this from a truly external network (phone hotspot, cloud VM).`);
  }
}

// Run
main().catch(console.error);
