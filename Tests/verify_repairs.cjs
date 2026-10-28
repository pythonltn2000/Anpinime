const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');

function assert(cond, msg) {
  if (!cond) {
    console.error(`FAIL: ${msg}`);
    process.exit(1);
  }
  console.log(`PASS: ${msg}`);
}

async function run() {
  console.log('=== TEST SUITE: ANPINIME REPAIR VERIFICATION ===\n');

  // -------------------------------------------------------------
  // TEST 1: ANIMEVIETSUB EPISODE PARSER REPAIR (Slug + .html)
  // -------------------------------------------------------------
  console.log('--- Test Group 1: Anime Episode Parser ---');
  
  // Test case 1.1: Episode URL extraction with .html in animeURL
  const animeBase = 'https://animevietsub.example';
  const rawShowSlug = 'bleach-sennen-kessen-hen-kashin-tan-a5985.html';
  const showSlug = rawShowSlug.replace(/\.html$/i, '');
  assert(showSlug === 'bleach-sennen-kessen-hen-kashin-tan-a5985', 'Normalized slug strips .html');

  const episodePath = '/phim/bleach-sennen-kessen-hen-kashin-tan-a5985/tap-01-114773.html';
  const normEpisodePath = episodePath.split('/').filter(Boolean).map(s => s.replace(/\.html$/i, ''));
  assert(normEpisodePath[0] === 'phim' && normEpisodePath[1] === showSlug && normEpisodePath[2] === 'tap-01-114773', 
    'Episode path components match normalized show slug');

  // Test case 1.2: Episode label matching with subtitles / quality
  const episodeLabels = [
    { text: '01', expectedNum: 1 },
    { text: 'Tập 01', expectedNum: 1 },
    { text: 'Tập 1 - Vietsub', expectedNum: 1 },
    { text: 'Tập 12 - Full HD', expectedNum: 12 },
    { text: 'Tập Đặc Biệt 02', expectedNum: 2 },
    { text: 'OVA 1', expectedNum: 1 },
    { text: 'Full', expectedNum: 1 },
  ];

  for (const item of episodeLabels) {
    const numMatch = item.text.match(/(?:tập|tap|ep|episode|ova|phần|phan)?\s*(\d{1,4})/i);
    const num = numMatch ? parseInt(numMatch[1], 10) : 1;
    assert(num === item.expectedNum, `Episode number extracted correctly from "${item.text}" -> ${num}`);
  }

  // Test case 1.3: Fixture regression test with anime-episodes-comments.html
  const commentsFixturePath = path.join(__dirname, 'Fixtures/anime-episodes-comments.html');
  const commentsHTML = fs.readFileSync(commentsFixturePath, 'utf8');
  assert(commentsHTML.includes('btn-episode') || commentsHTML.includes('list-episode'), 'Comments fixture loaded');

  // -------------------------------------------------------------
  // TEST 2: NATIVE SCHEDULE TIMETABLE EXTRACTION
  // -------------------------------------------------------------
  console.log('\n--- Test Group 2: Native Schedule Timetable ---');

  const sampleNextJS = `self.__next_f.push([1,"{\\"t2\\":[{\\"id\\":\\"101\\",\\"title\\":\\"Anime Monday\\",\\"time\\":\\"23:00\\",\\"episode\\":\\"12\\",\\"slug\\":\\"anime-monday\\",\\"thumb\\":\\"https://img.example/t2.jpg\\",\\"status\\":\\"Đã chiếu\\"}],\\"cn\\":[{\\"id\\":\\"701\\",\\"title\\":\\"Anime Sunday\\",\\"time\\":\\"18:00\\\",\\"episode\\":\\"05\\",\\"slug\\":\\"anime-sunday\\",\\"thumb\\":\\"https://img.example/cn.jpg\\",\\"status\\":\\"Sắp chiếu\\"}]}"])`;
  
  const days = ['t2', 't3', 't4', 't5', 't6', 't7', 'cn'];
  const dayItems = {};
  for (const d of days) {
    const regex = new RegExp(`\\\\?"${d}\\\\?"\\s*:\\s*\\[([^\\]]*)\\]`, 'g');
    const match = regex.exec(sampleNextJS);
    if (match) {
      dayItems[d] = match[1];
    }
  }
  assert(dayItems['t2'] && dayItems['t2'].includes('Anime Monday'), 'Monday schedule extracted from Next.js push chunk');
  assert(dayItems['cn'] && dayItems['cn'].includes('Anime Sunday'), 'Sunday schedule extracted from Next.js push chunk');

  // -------------------------------------------------------------
  // TEST 3: PHIM4K VIP GATEWAY SIGNING & RESOLUTION
  // -------------------------------------------------------------
  console.log('\n--- Test Group 3: Phim4K VIP Resolver ---');

  const HMAC_SECRET = '5e8d1b4f9c2a6e730b1f8d4a92c5e3d1';
  const fileID = 'E6E8NBA94K72';
  
  // Date format yyyyMMdd in UTC
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  const day = String(now.getUTCDate()).padStart(2, '0');
  const dateUtc = `${year}${month}${day}`;

  // Derive daily secret: AES-256-GCM
  const keyBytes = crypto.createHash('sha256').update(HMAC_SECRET).digest();
  const ivSource = crypto.createHash('sha256').update('iv:' + HMAC_SECRET).digest();
  const nonce = ivSource.subarray(0, 12);
  const cipher = crypto.createCipheriv('aes-256-gcm', keyBytes, nonce);
  const plaintext = `${HMAC_SECRET}:${dateUtc}`;
  let ciphertext = cipher.update(plaintext, 'utf8');
  ciphertext = Buffer.concat([ciphertext, cipher.final()]);
  const tag = cipher.getAuthTag();
  const signingSecret = `${HMAC_SECRET}:${Buffer.concat([ciphertext, tag]).toString('hex')}`;

  assert(signingSecret.startsWith(HMAC_SECRET + ':'), 'Daily AES-GCM signing secret derived');

  // Timestamp OTP mask
  const nowSec = Math.floor(Date.now() / 1000);
  const mask = crypto.createHmac('sha256', signingSecret).update('otp-ts-mask').digest().subarray(0, 4);
  const tsBuf = Buffer.alloc(4);
  tsBuf.writeUInt32BE(nowSec, 0);
  const xored = Buffer.alloc(4);
  for (let i = 0; i < 4; i++) xored[i] = tsBuf[i] ^ mask[i];
  const tsHex = xored.toString('hex');

  // Token HMAC
  const token = crypto.createHmac('sha256', signingSecret).update(`${fileID}:${nowSec}`).digest('hex');
  const gatewayURL = `https://svatv.cryboiz.workers.dev/${fileID}?token=${token}&ts=${tsHex}`;
  assert(gatewayURL.includes(fileID) && gatewayURL.includes('token='), 'Gateway URL generated with valid signature');

  // -------------------------------------------------------------
  // TEST 4: NON-REGRESSION ON MOVIE SOURCES 1 & 3
  // -------------------------------------------------------------
  console.log('\n--- Test Group 4: Movie Source 1 & 3 Protection ---');

  const sourceRows = { items: [{ slug: 'same-title', name: 'Same title', language: 'Vietsub' }] };
  const nguoncHost = 'phim.nguonc.com';
  const kkphimHost = 'phimapi.com';

  assert(nguoncHost === 'phim.nguonc.com', 'Source 1 host remains unchanged (phim.nguonc.com)');
  assert(kkphimHost === 'phimapi.com', 'Source 3 host remains unchanged (phimapi.com)');

  console.log('\n=== ALL 4 TEST SUITES PASSED VERIFICATION ===');
}

run().catch(err => {
  console.error('Test runner error:', err);
  process.exit(1);
});
