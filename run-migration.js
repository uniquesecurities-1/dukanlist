// =====================================================
// run-migration.js
// Apply SQL migrations directly to Supabase — no dashboard needed
// =====================================================
//
// HOW TO USE:
//   1. Open PowerShell / Command Prompt in E:\dukanlist-web
//   2. Run:  node run-migration.js db/24-admin-disabled-flag.sql
//   3. Paste your Supabase Database password when asked
//   4. Done — SQL executes directly via Supabase's REST API
//
// WHERE TO GET YOUR DATABASE PASSWORD:
//   Aap project setup time pe ye password save karke rakha tha.
//   Agar bhool gaye to:
//     Supabase Dashboard → Project → Settings → Database
//     "Database password" section me "Reset database password" button hai
//     (Reset karte hi ek naya password milega — wo paste karo)
//
//   NOTE: Ye database password Supabase login password se ALAG hai.
//   Database password = postgres user ka password (project-specific).
// =====================================================

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execSync } = require('child_process');

const PROJECT_REF = 'qazuyygrpqopwygxmvwq';

const args = process.argv.slice(2);
if (args.length === 0) {
  console.error('\n❌ Usage: node run-migration.js <path-to-sql-file>');
  console.error('   Example: node run-migration.js db/24-admin-disabled-flag.sql\n');
  process.exit(1);
}

const sqlPath = args[0];
if (!fs.existsSync(sqlPath)) {
  console.error('❌ File not found: ' + sqlPath);
  process.exit(1);
}

const sql = fs.readFileSync(sqlPath, 'utf8');
console.log('\n📄 Loaded: ' + sqlPath);
console.log('   Size: ' + sql.length + ' chars\n');

// Hidden password prompt
function askPassword(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    // Hide input
    process.stdout.write(question);
    const stdin = process.openStdin();
    let pw = '';
    process.stdin.on('data', (char) => {
      char = char.toString();
      if (char === '\n' || char === '\r' || char === '') {
        process.stdout.write('\n');
        stdin.pause();
        rl.close();
        resolve(pw);
      } else if (char === '') {
        process.exit();
      } else if (char === '' || char === '\b') {
        pw = pw.slice(0, -1);
      } else {
        pw += char;
        process.stdout.write('*');
      }
    });
  });
}

async function main() {
  console.log('🔑 Supabase Database password chahiye.');
  console.log('   (Dashboard → Project Settings → Database → Database password)\n');
  const password = await askPassword('   Password: ');

  if (!password || password.length < 6) {
    console.error('\n❌ Password too short. Aborting.');
    process.exit(1);
  }

  console.log('\n⏳ Connecting to Supabase database…');

  // Build connection string for Supabase's session pooler (works on most networks)
  // Format: postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
  // We try the direct connection first, then fall back to pooler.
  const encPw = encodeURIComponent(password);

  // Try psql via npx (uses bundled node-postgres equivalent)
  // We'll use the `pg` npm package — install it on the fly if missing
  let pg;
  try {
    pg = require('pg');
  } catch (e) {
    console.log('   Installing pg driver (one-time, ~5 sec)…');
    try {
      execSync('npm install pg --no-save --silent', { stdio: 'inherit' });
      pg = require('pg');
    } catch (err) {
      console.error('\n❌ Could not install "pg" npm package.');
      console.error('   Run manually:  npm install pg');
      console.error('   Then re-run:   node run-migration.js ' + sqlPath);
      process.exit(1);
    }
  }

  // Try direct connection first
  const directHost = 'db.' + PROJECT_REF + '.supabase.co';
  const poolerHost = 'aws-0-ap-south-1.pooler.supabase.com';

  async function tryConnect(host, user, port) {
    const client = new pg.Client({
      host: host,
      port: port,
      database: 'postgres',
      user: user,
      password: password,
      ssl: { rejectUnauthorized: false },
      connectionTimeoutMillis: 8000
    });
    await client.connect();
    return client;
  }

  let client;
  try {
    console.log('   Trying direct: ' + directHost + ':5432 …');
    client = await tryConnect(directHost, 'postgres', 5432);
    console.log('   ✓ Connected (direct)');
  } catch (e1) {
    console.log('   Direct failed (' + e1.code + '). Trying pooler…');
    try {
      client = await tryConnect(poolerHost, 'postgres.' + PROJECT_REF, 5432);
      console.log('   ✓ Connected (pooler)');
    } catch (e2) {
      console.error('\n❌ Could not connect to database.');
      console.error('   Direct error: ' + (e1.message || e1.code));
      console.error('   Pooler error: ' + (e2.message || e2.code));
      console.error('\n   Likely causes:');
      console.error('   • Wrong password (Database password ≠ login password)');
      console.error('   • Network firewall blocking outbound 5432');
      console.error('\n   Try resetting password: Dashboard → Settings → Database → Reset DB password');
      process.exit(1);
    }
  }

  console.log('\n⚡ Executing SQL…\n');

  try {
    const result = await client.query(sql);
    console.log('✅ Migration applied successfully!');
    if (Array.isArray(result) && result.length) {
      console.log('   ' + result.length + ' statement(s) executed.');
    }
  } catch (err) {
    console.error('\n❌ SQL error:');
    console.error('   ' + err.message);
    if (err.position) console.error('   At position: ' + err.position);
    if (err.hint) console.error('   Hint: ' + err.hint);
    process.exit(1);
  } finally {
    await client.end();
  }

  console.log('\n🎉 Done. Migration ' + path.basename(sqlPath) + ' applied to Supabase.');
}

main().catch(err => {
  console.error('\n💥 Unexpected error:', err.message);
  process.exit(1);
});
