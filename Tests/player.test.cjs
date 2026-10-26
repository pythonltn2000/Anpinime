const {readFileSync} = require('node:fs');
const assert = require('node:assert/strict');
const {JSDOM} = require('jsdom');
const swift = readFileSync('AnyAnime/PlayerView.swift', 'utf8');
const script = swift.match(/private var fallbackJavaScript: String \{\s*"""([\s\S]*?)"""/)[1].replace(/\\\\/g, '\\');
new Function(script);

function fixture(html) {
  const dom = new JSDOM(html, {url: 'https://animevietsub.example/watch', runScripts: 'outside-only', pretendToBeVisual: true});
  const w = dom.window, messages = [], intervals = [];
  w.webkit = {messageHandlers: new Proxy({}, {get: (_, name) => ({postMessage: value => messages.push({name, value})})})};
  w.setInterval = fn => { intervals.push(fn); return intervals.length; };
  w.setTimeout = () => 1;
  Object.defineProperty(w.document, 'readyState', {value: 'complete'});
  const video = w.document.querySelector('video');
  let paused = true, plays = 0;
  if (video) {
    Object.defineProperties(video, {
      paused: {get: () => paused}, duration: {get: () => 180}, readyState: {get: () => 4}
    });
    video.play = () => { paused = false; plays++; return Promise.resolve(); };
    video.pause = () => { paused = true; };
  }
  w.eval(script);
  return {dom, w, messages, video, intervals, get plays(){return plays;},
    command(name, value = 0) { w.dispatchEvent(new w.MessageEvent('message', {data:{type:'AnPinimeCommand', name, value}})); }};
}

const f = fixture('<title>Xem phim</title><body><header>Navigation</header><main><div id="media-player"><video src="https://cdn.example/movie.mp4"></video><div>Old controls</div></div></main><footer>Ad links</footer></body>');
assert.equal(f.w.document.querySelector('meta[name="viewport"]').content, 'width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover');
assert.equal(f.video.style.objectFit, 'contain', 'Default fit preserves the original video ratio');
assert.equal(f.video.style.transform, 'none', 'Site transforms must not offset the video');
assert.equal(f.video.style.boxSizing, 'border-box');
assert.equal(f.video.style.position, 'fixed');
assert.equal(f.video.style.width, '100vw');
assert.equal(f.w.document.querySelector('header').style.display, 'none');
assert.equal(f.plays, 1);
assert(f.messages.some(m => m.name === 'videoFound' && m.value.url === 'https://cdn.example/movie.mp4'), 'Restore web-to-native video handoff before waiting for frames');
f.command('pause');
f.w.__anyanimeFocusPlayer();
assert.equal(f.video.paused, true, 'DOM updates must not override user pause');
assert.equal(f.plays, 1);
f.video.dispatchEvent(new f.w.Event('canplay'));
assert.equal(f.video.paused, true, 'canplay must respect an explicit user pause');
f.command('seek', 999);
assert.equal(f.video.currentTime, 180, 'Seek clamps to duration');
f.command('seek', -20);
assert.equal(f.video.currentTime, 0);
f.command('rate', 1.5);
assert.equal(f.video.playbackRate, 1.5);
f.command('fit', 1);
f.w.__anyanimeFocusPlayer();
assert.equal(f.video.style.objectFit, 'cover', 'Fill preference survives DOM changes');
f.command('play');
assert.equal(f.video.paused, false);
assert(f.messages.some(m => m.name === 'mediaState' && m.value.ready && m.value.duration === 180));
f.dom.window.close();

const n = fixture('<title>Xem phim</title><body><p class="notice">Nếu bạn không thể truy cập AnimeVietsub, hãy thử tên miền khác.</p><video src="https://cdn.example/movie.mp4"></video></body>');
assert.equal(n.w.document.querySelector('.notice').style.display, 'none', 'Hide the AnimeVietsub access notice from the player');
n.dom.window.close();

const c = fixture('<title>Just a moment...</title><body><header>Verify</header><form id="challenge-form"><input type="checkbox"></form></body>');
assert.equal(c.w.__anyanimeFocusPlayer(), false);
assert.notEqual(c.w.document.querySelector('header').style.display, 'none', 'Keep real challenge usable');
assert(!c.messages.some(m => m.name === 'playerReady'));
c.dom.window.close();
console.log('PASS: fullscreen isolation, playback commands, access notice filtering, pause preservation, seek limits, fill persistence and challenge visibility');
