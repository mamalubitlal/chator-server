/**
 * TURN ALLOCATE test — generates fresh credentials from shared secret
 * (same flow as turnutils_uclient -W <secret>).
 *
 * Usage:
 *   node test_real_creds.js [host] [port] [shared_secret]
 *
 * Examples:
 *   node test_real_creds.js
 *   node test_real_creds.js 192.168.0.11 3478 chator-test-secret
 */
const dgram = require('dgram');
const crypto = require('crypto');

const HOST = process.argv[2] || '192.168.0.11';
const PORT = parseInt(process.argv[3] || '3478', 10);
const SHARED_SECRET = process.argv[4] || 'chator-test-secret';
const TIMEOUT = parseInt(process.argv[5] || '5000', 10);

// Generate fresh credentials (like turnutils -W does)
const TS = Math.floor(Date.now() / 1000);
const USERNAME = `${TS}`;
const PASSWORD = crypto.createHmac('sha1', SHARED_SECRET).update(USERNAME).digest('base64');

const MAGIC_COOKIE = 0x2112A442;
const ALLOCATE_REQ = 0x0003;
const ALLOCATE_RES = 0x0103;
const ALLOCATE_ERR = 0x0113;
const ATTR_USERNAME = 0x0006;
const ATTR_MI = 0x0008;
const ATTR_ERROR = 0x0009;
const ATTR_REALM = 0x0014;
const ATTR_NONCE = 0x0015;
const ATTR_XOR_RELAYED = 0x0016;
const ATTR_REQ_TRANSPORT = 0x0019;
const ATTR_LIFETIME = 0x000D;
const ATTR_FINGERPRINT = 0x8028;
const FINGERPRINT_XOR = 0x5354554E;

function pad4(n) { while (n % 4) n++; return n; }

// CRC32 for FINGERPRINT
function crc32(buf) {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    table[i] = c;
  }
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xFF] ^ (crc >>> 8);
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function parseAttrs(msg, off, len) {
  const a = {};
  while (off < 20 + len && off + 4 <= msg.length) {
    const t = msg.readUInt16BE(off), l = msg.readUInt16BE(off + 2);
    const pl = pad4(l);
    if (off + 4 + l > msg.length) break;
    a[t] = msg.slice(off + 4, off + 4 + l);
    off += 4 + pl;
  }
  return a;
}

function sendOne(sock, pkt) {
  return new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error('timeout')), TIMEOUT);
    sock.once('message', raw => { clearTimeout(t); res(raw); });
    sock.send(pkt, PORT, HOST, e => { if (e) rej(e); });
  });
}

async function main() {
  console.log('═══ TURN ALLOCATE (fresh creds from shared secret) ═══\n');
  console.log(`  Server:       ${HOST}:${PORT}`);
  console.log(`  Shared Sec:   ${SHARED_SECRET}`);
  console.log(`  Username:     ${USERNAME}`);
  console.log(`  Password:     ${PASSWORD}\n`);

  const sock = dgram.createSocket('udp4');
  sock.on('error', () => {});

  // Step 1: ALLOCATE without auth → get nonce
  console.log('── Step 1: Unauthenticated ALLOCATE ──');
  const tx1 = crypto.randomBytes(12);
  const transport = Buffer.alloc(8);
  transport.writeUInt16BE(ATTR_REQ_TRANSPORT, 0);
  transport.writeUInt16BE(4, 2);
  transport.writeUInt8(17, 4);
  transport.fill(0, 5);

  const p1 = Buffer.alloc(20 + 8);
  p1.writeUInt16BE(ALLOCATE_REQ, 0);
  p1.writeUInt16BE(8, 2);
  p1.writeUInt32BE(MAGIC_COOKIE, 4);
  tx1.copy(p1, 8);
  transport.copy(p1, 20);

  const r1 = await sendOne(sock, p1);
  const attrs1 = parseAttrs(r1, 20, r1.readUInt16BE(2));
  const realm = (attrs1[ATTR_REALM] || Buffer.from('chator.local')).toString('utf8');
  const nonce = attrs1[ATTR_NONCE].toString('utf8');
  console.log(`  Nonce: ${nonce}`);
  console.log(`  Realm: ${realm}\n`);

  // Step 2: ALLOCATE with auth
  console.log('── Step 2: Authenticated ALLOCATE ──');
  const tx2 = crypto.randomBytes(12);

  // Build attributes in order similar to turnutils:
  // REQ-TRANSPORT + LIFETIME + USERNAME + NONCE + REALM + MI + FINGERPRINT

  const ub = Buffer.from(USERNAME, 'utf8');
  const ua = Buffer.alloc(4 + pad4(ub.length));
  ua.writeUInt16BE(ATTR_USERNAME, 0);
  ua.writeUInt16BE(ub.length, 2);
  ub.copy(ua, 4);

  const rb = Buffer.from(realm, 'utf8');
  const ra = Buffer.alloc(4 + pad4(rb.length));
  ra.writeUInt16BE(ATTR_REALM, 0);
  ra.writeUInt16BE(rb.length, 2);
  rb.copy(ra, 4);

  const nb = Buffer.from(nonce, 'utf8');
  const na = Buffer.alloc(4 + pad4(nb.length));
  na.writeUInt16BE(ATTR_NONCE, 0);
  na.writeUInt16BE(nb.length, 2);
  nb.copy(na, 4);

  const lifetimeVal = Buffer.alloc(4);
  lifetimeVal.writeUInt32BE(600, 0); // 10 min
  const la = Buffer.alloc(8);
  la.writeUInt16BE(ATTR_LIFETIME, 0);
  la.writeUInt16BE(4, 2);
  lifetimeVal.copy(la, 4);

  const hdr = Buffer.alloc(20);
  hdr.writeUInt16BE(ALLOCATE_REQ, 0);
  hdr.writeUInt16BE(0, 2);
  hdr.writeUInt32BE(MAGIC_COOKIE, 4);
  tx2.copy(hdr, 8);

  // Attributes before MI (in turnutils-compatible order)
  const preMiBody = Buffer.concat([transport, la, ua, na, ra]);
  const bodyLen = preMiBody.length;

  // Build MI placeholder IN the buffer BEFORE HMAC (per RFC 5389)
  const miPlaceholder = Buffer.alloc(24);
  miPlaceholder.writeUInt16BE(ATTR_MI, 0);
  miPlaceholder.writeUInt16BE(20, 2);

  const preHmac = Buffer.concat([hdr, preMiBody, miPlaceholder]);
  preHmac.writeUInt16BE(bodyLen + 24, 2);

  // MI key = MD5(username:realm:password)
  const miKey = crypto.createHash('md5').update(`${USERNAME}:${realm}:${PASSWORD}`).digest();
  const hmac = crypto.createHmac('sha1', miKey).update(preHmac).digest();

  // Overwrite MI placeholder value bytes with computed HMAC
  hmac.copy(preHmac, 20 + bodyLen + 4);

  // RFC 5389 §15.5: message length field MUST include FINGERPRINT attr when computing CRC
  preHmac.writeUInt16BE(bodyLen + 24 + 8, 2);
  // Add FINGERPRINT (CRC32 of everything up to and excluding the fingerprint attr itself)
  const crc = crc32(preHmac);
  const fpVal = Buffer.alloc(4);
  fpVal.writeUInt32BE((crc ^ FINGERPRINT_XOR) >>> 0, 0);
  const fpAttr = Buffer.alloc(8);
  fpAttr.writeUInt16BE(ATTR_FINGERPRINT, 0);
  fpAttr.writeUInt16BE(4, 2);
  fpVal.copy(fpAttr, 4);

  const pkt = Buffer.concat([preHmac, fpAttr]);

  // DEBUG: dump request hex
  console.log('  ── Request hex dump (body only):');
  for (let i = 20; i < pkt.length; i += 16) {
    const hex = Array.from(pkt.slice(i, Math.min(i+16, pkt.length))).map(b => b.toString(16).padStart(2, '0')).join(' ');
    console.log(`     ${hex}`);
  }

  const r2 = await sendOne(sock, pkt);
  const type2 = r2.readUInt16BE(0);
  const attrs2 = parseAttrs(r2, 20, r2.readUInt16BE(2));

  sock.close();

  if (type2 === ALLOCATE_RES) {
    let relay = '';
    let lifetime = 0;
    if (attrs2[ATTR_LIFETIME]) lifetime = attrs2[ATTR_LIFETIME].readUInt32BE(0);
    if (attrs2[ATTR_XOR_RELAYED]) {
      const b = attrs2[ATTR_XOR_RELAYED];
      const port = b.readUInt16BE(2) ^ (MAGIC_COOKIE >> 16);
      if (b.readUInt8(1) === 1) {
        relay = [0,1,2,3].map(i => b.readUInt8(4+i) ^ ((MAGIC_COOKIE >> ((3-i)*8)) & 0xFF)).join('.') + ':' + port;
      }
    }
    console.log('  ✅ ALLOCATE SUCCESS!');
    console.log(`  Relay:    ${relay}`);
    console.log(`  Lifetime: ${lifetime}s\n`);
    return true;
  } else {
    let err = 'unknown';
    if (attrs2[ATTR_ERROR]) {
      const b = attrs2[ATTR_ERROR];
      err = `${b.readUInt8(2)}${String(b.readUInt8(3)).padStart(2, '0')} - ${b.toString('utf8', 4).replace(/\0/g, '')}`;
    }
    console.log(`  ❌ FAILED: ${err}\n`);
    return false;
  }
}

main().catch(e => { console.error(`\n  FATAL: ${e.message}`); process.exit(1); });
