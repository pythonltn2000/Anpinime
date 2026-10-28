const fs = require('fs');
const path = require('path');

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
  // This script only checks sample fixture shapes. The Swift parser/provider
  // suites exercise production code; no signing token or live result is implied.
  console.log('\nFixture shape checks passed. Run Swift tests for actual parser and provider behavior.');
}

run().catch(err => {
  console.error('Test runner error:', err);
  process.exit(1);
});
