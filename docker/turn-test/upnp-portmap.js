/**
 * UPnP Port Forwarding script for Synapse/Matrix.
 *
 * Maps external ports → internal IP using router UPnP.
 *
 * Usage:
 *   node upnp-portmap.js              # show current mappings
 *   node upnp-portmap.js add          # add Synapse port mappings
 *   node upnp-portmap.js remove       # remove Synapse port mappings
 *   node upnp-portmap.js list         # list all gateway mappings
 */
const { createClient } = require('nat-upnp');
const client = createClient();

const INTERNAL_IP = '192.168.0.11';

// Port mappings: [externalPort, internalPort, description]
const MAPPINGS = [
  [8008, 8008, 'chator Synapse (Matrix Client-Server)'],
  [8448, 8008, 'chator Synapse (Matrix Federation)'],
  [80, 80, 'chator Caddy HTTP redirect'],
  [443, 443, 'chator Caddy HTTPS'],
];

const TTL = 0; // 0 = permanent (until router reboot or removed)

function showUsage() {
  console.log(`
Usage: node upnp-portmap.js <action>

  list      Show all UPnP port mappings on the router
  add       Add Synapse port mappings (8008, 8448 → 192.168.0.15)
  remove    Remove Synapse port mappings
  (no arg)  Show current mappings (alias: list)
`);
}

async function listMappings() {
  return new Promise((resolve, reject) => {
    client.getMappings((err, mappings) => {
      if (err) return reject(err);
      resolve(mappings || []);
    });
  });
}

async function addMapping(externalPort, internalPort, description) {
  return new Promise((resolve, reject) => {
    client.portMapping({
      public: externalPort,
      private: internalPort,
      local: INTERNAL_IP,
      description,
      ttl: TTL,
      protocol: 'TCP',
    }, (err) => {
      if (err) return reject(err);
      resolve();
    });
  });
}

async function removeMapping(publicPort, protocol = 'TCP') {
  return new Promise((resolve, reject) => {
    client.portUnmapping({
      public: publicPort,
      protocol,
    }, (err) => {
      if (err) return reject(err);
      resolve();
    });
  });
}

async function showMappings() {
  console.log('\n🔍 Current UPnP Port Mappings:\n');
  const mappings = await listMappings();
  if (mappings.length === 0) {
    console.log('  (no mappings found)');
  } else {
    for (const m of mappings) {
      const flags = [];
      if (m.enabled) flags.push('✅');
      if (m.description?.includes('chator')) flags.push('📌');
      console.log(`  ${flags.join(' ')} ${m.public.port || m.public}/${m.protocol || 'TCP'} → ${m.private?.host || '?'}:${m.private?.port || m.public}`);
      if (m.description) console.log(`       Description: ${m.description}`);
      if (m.ttl) console.log(`       TTL: ${m.ttl}s`);
    }
  }
  console.log();
}

async function addSynapseMappings() {
  console.log('\n➕ Adding Synapse UPnP port mappings...\n');
  for (const [ext, int, desc] of MAPPINGS) {
    try {
      await addMapping(ext, int, desc);
      console.log(`  ✅ ${ext} (TCP) → ${INTERNAL_IP}:${int}  — ${desc}`);
    } catch (err) {
      if (err.message?.includes('ConflictInMappingEntry') || err.message?.includes('conflict')) {
        console.log(`  ⚠️  ${ext} (TCP) → ${INTERNAL_IP}:${int}  — already mapped (conflict, skipping)`);
      } else {
        console.log(`  ❌ ${ext} (TCP) → ${INTERNAL_IP}:${int}  — FAILED: ${err.message}`);
      }
    }
  }
  console.log();
}

async function removeSynapseMappings() {
  console.log('\n➖ Removing Synapse UPnP port mappings...\n');
  for (const [ext, int, desc] of MAPPINGS) {
    try {
      await removeMapping(ext, 'TCP');
      console.log(`  ✅ Removed ${ext} (TCP)`);
    } catch (err) {
      console.log(`  ⚠️  ${ext} (TCP) — ${err.message}`);
    }
  }
  console.log();
}

async function main() {
  const action = process.argv[2] || 'list';

  switch (action) {
    case 'list':
      await showMappings();
      break;
    case 'add':
      await addSynapseMappings();
      console.log('Verifying...');
      await showMappings();
      break;
    case 'remove':
      await removeSynapseMappings();
      console.log('Verifying...');
      await showMappings();
      break;
    default:
      showUsage();
      process.exit(1);
  }

  client.close();
}

main().catch(err => {
  console.error('FATAL:', err.message);
  client.close();
  process.exit(1);
});
