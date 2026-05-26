/**
 * TURN ALLOCATE test for coturn with use-auth-secret.
 * Flow: send ALLOCATE without auth → get 401 + nonce → retry with credentials.
 * Usage: node test_turn_allocate.js <host> [port] [secret]
 */

const dgram = require('dgram');
const crypto = require('crypto');

const HOST = process.argv[2] || '192.168.0.11';
const PORT = parseInt(process.argv[3] || '3478', 10);
const SHARED_SECRET = process.argv[4] || 'chator-test-secret';
const TIMEOUT = 5000;

const MAGIC_COOKIE = 0x2112A442;

const ALLOCATE_REQUEST = 0x0003;
const ALLOCATE_RESPONSE = 0x0103;
const ALLOCATE_ERROR_RESPONSE = 0x0113;

const ATTR_USERNAME = 0x0006;
const ATTR_MESSAGE_INTEGRITY = 0x0008;
const ATTR_ERROR_CODE = 0x0009;
const ATTR_REALM = 0x0014;
const ATTR_NONCE = 0x0015;
const ATTR_REQUESTED_TRANSPORT = 0x0019;
const ATTR_LIFETIME = 0x000D;
const ATTR_XOR_RELAYED_ADDRESS = 0x0016;

function pad4(len) { while (len % 4 !== 0) len++; return len; }

function parseAttrs(msg, offset, len) {
  const attrs = {};
  while (offset < 20 + len && offset + 4 <= msg.length) {
    const type = msg.readUInt16BE(offset);
    const attrLen = msg.readUInt16BE(offset + 2);
    const paddedLen = pad4(attrLen);
    if (offset + 4 + attrLen > msg.length) break;
    attrs[type] = msg.slice(offset + 4, offset + 4 + attrLen);
    offset += 4 + paddedLen;
  }
  return attrs;
}

function generatePassword(username, secret) {
  return crypto.createHmac('sha1', Buffer.from(secret, 'utf8'))
    .update(Buffer.from(username, 'utf8'))
    .digest('base64');
}

// RFC 5389 long-term credential key = MD5(username:realm:password)
function miKey(username, realm, password) {
  return crypto.createHash('md5')
    .update(`${username}:${realm}:${password}`)
    .digest();
}

function createTimeUsername(base) {
  return `${Math.floor(Date.now() / 1000)}:${base}`;
}

function sendAndWait(sock, packet, filterFn) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), TIMEOUT);
    sock.once('message', raw => {
      clearTimeout(t);
      if (filterFn && !filterFn(raw)) return; // keep waiting (but once only fires once...)
      const type = raw.readUInt16BE(0);
      const len = raw.readUInt16BE(2);
      resolve({ type, len, raw, attrs: parseAttrs(raw, 20, len) });
    });
    sock.send(packet, PORT, HOST, err => { if (err) reject(err); });
  });
}

async function main() {
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║     TURN ALLOCATE Test                      ║');
  console.log('╚══════════════════════════════════════════════╝');
  console.log(`  Server:  ${HOST}:${PORT}`);
  console.log(`  Secret:  ${SHARED_SECRET}\n`);

  const sock = dgram.createSocket('udp4');
  sock.on('error', () => {});

  // Step 1: Send ALLOCATE WITHOUT auth → expect 401 with nonce
  console.log('── Step 1: ALLOCATE (no auth, expect 401) ──');
  
  const txId1 = crypto.randomBytes(12);
  const transport = Buffer.alloc(8);
  transport.writeUInt16BE(ATTR_REQUESTED_TRANSPORT, 0);
  transport.writeUInt16BE(4, 2);
  transport.writeUInt8(17, 4);
  transport.fill(0, 5);

  const pkt1 = Buffer.alloc(20 + transport.length);
  pkt1.writeUInt16BE(ALLOCATE_REQUEST, 0);
  pkt1.writeUInt16BE(transport.length, 2);
  pkt1.writeUInt32BE(MAGIC_COOKIE, 4);
  txId1.copy(pkt1, 8);
  transport.copy(pkt1, 20);

  const r1 = await sendAndWait(sock, pkt1);
  console.log(`  Response type: 0x${r1.type.toString(16)}`);

  if (r1.type !== ALLOCATE_ERROR_RESPONSE) {
    console.log(`  ❌ Expected error response, got 0x${r1.type.toString(16)}`);
    sock.close();
    process.exit(1);
  }

  const realmStr = r1.attrs[ATTR_REALM]?.toString('utf8') || 'chator.local';
  const nonceStr = r1.attrs[ATTR_NONCE]?.toString('utf8');

  let errCode = 'unknown';
  if (r1.attrs[ATTR_ERROR_CODE]) {
    const b = r1.attrs[ATTR_ERROR_CODE];
    errCode = `${b.readUInt8(2)}${String(b.readUInt8(3)).padStart(2, '0')} - ${b.toString('utf8', 4).replace(/\0/g, '')}`;
  }
  console.log(`  Error:             ${errCode}`);
  console.log(`  Realm (from 401):  ${realmStr}`);
  console.log(`  Nonce (from 401):  ${nonceStr}\n`);

  if (!nonceStr) {
    console.log('  ❌ No nonce received');
    sock.close();
    process.exit(1);
  }

  // Step 2: Retry ALLOCATE with credentials
  console.log('── Step 2: ALLOCATE with credentials ──');

  const username = createTimeUsername('chator_test');
  const password = generatePassword(username, SHARED_SECRET);
  console.log(`  Username: ${username}`);
  console.log(`  Password: ${password}`);

  const txId2 = crypto.randomBytes(12);

  // Build attributes
  const ub = Buffer.from(username, 'utf8');
  const uattr = Buffer.alloc(4 + pad4(ub.length));
  uattr.writeUInt16BE(ATTR_USERNAME, 0);
  uattr.writeUInt16BE(ub.length, 2);
  ub.copy(uattr, 4);

  const rb = Buffer.from(realmStr, 'utf8');
  const rattr = Buffer.alloc(4 + pad4(rb.length));
  rattr.writeUInt16BE(ATTR_REALM, 0);
  rattr.writeUInt16BE(rb.length, 2);
  rb.copy(rattr, 4);

  const nb = Buffer.from(nonceStr, 'utf8');
  const nattr = Buffer.alloc(4 + pad4(nb.length));
  nattr.writeUInt16BE(ATTR_NONCE, 0);
  nattr.writeUInt16BE(nb.length, 2);
  nb.copy(nattr, 4);

  // Header
  const hdr2 = Buffer.alloc(20);
  hdr2.writeUInt16BE(ALLOCATE_REQUEST, 0);
  hdr2.writeUInt16BE(0, 2);
  hdr2.writeUInt32BE(MAGIC_COOKIE, 4);
  txId2.copy(hdr2, 8);

  const preMiBody = Buffer.concat([transport, uattr, rattr, nattr]);
  const bodyLen = preMiBody.length;

  // MESSAGE-INTEGRITY — key = MD5(username:realm:password) per RFC 5389
  const key = miKey(username, realmStr, password);

  // Build message: header + attributes (WITHOUT MI attribute)
  // coturn computes HMAC over message excluding the MI attribute entirely
  const msgCore = Buffer.concat([hdr2, preMiBody]);
  // Set header length to account for MI attribute that will be appended
  msgCore.writeUInt16BE(bodyLen + 24, 2);

  // Compute HMAC over header + attributes (no MI attr included)
  const miVal = crypto.createHmac('sha1', key).update(msgCore).digest();

  // Now build MI attribute and append it
  const miAttr = Buffer.alloc(24);
  miAttr.writeUInt16BE(ATTR_MESSAGE_INTEGRITY, 0);
  miAttr.writeUInt16BE(20, 2);
  miVal.copy(miAttr, 4);

  const pkt2 = Buffer.concat([msgCore, miAttr]);

  const r2 = await sendAndWait(sock, pkt2);
  console.log(`  Response type: 0x${r2.type.toString(16)}`);

  sock.close();
  console.log();

  if (r2.type === ALLOCATE_RESPONSE) {
    let relayAddr = '', lifetime = 0;
    if (r2.attrs[ATTR_LIFETIME]) lifetime = r2.attrs[ATTR_LIFETIME].readUInt32BE(0);
    if (r2.attrs[ATTR_XOR_RELAYED_ADDRESS]) {
      const b = r2.attrs[ATTR_XOR_RELAYED_ADDRESS];
      const fam = b.readUInt8(1);
      const port = b.readUInt16BE(2) ^ (MAGIC_COOKIE >> 16);
      if (fam === 1) {
        relayAddr = [0,1,2,3].map(i => b.readUInt8(4+i) ^ ((MAGIC_COOKIE >> ((3-i)*8)) & 0xFF)).join('.') + ':' + port;
      }
    }
    console.log('  ✅ TURN ALLOCATE SUCCESS!');
    console.log(`  Relay Address: ${relayAddr}`);
    console.log(`  Lifetime:      ${lifetime}s\n`);
    console.log('  🎉 TURN relay allocation is working!\n');
  } else if (r2.type === ALLOCATE_ERROR_RESPONSE) {
    let err = 'unknown';
    if (r2.attrs[ATTR_ERROR_CODE]) {
      const b = r2.attrs[ATTR_ERROR_CODE];
      err = `${b.readUInt8(2)}${String(b.readUInt8(3)).padStart(2, '0')} - ${b.toString('utf8', 4).replace(/\0/g, '')}`;
    }
    console.log(`  ❌ TURN ALLOCATE FAILED: ${err}\n`);
  } else {
    console.log(`  ❓ Unexpected: 0x${r2.type.toString(16)}\n`);
  }
}

main().catch(err => {
  console.error(`\n  ❌ FATAL: ${err.message}`);
  process.exit(1);
});
