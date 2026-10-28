const {readFileSync} = require('node:fs');
const assert = require('node:assert/strict');
const {JSDOM} = require('jsdom');
const swift = readFileSync('AnyAnime/PlayerView.swift', 'utf8');
const script = swift.match(/private var fallbackJavaScript: String \{\s*"""([\s\S]*?)"""/)[1].replace(/\\\\/g, '\\');
new Function(script);

function fixture(html, setup = () => {}) {
  const dom = new JSDOM(html, {url: 'https://animevietsub.example/watch', runScripts: 'outside-only', pretendToBeVisual: true});
  const w = dom.window, messages = [], intervals = [];
  w.webkit = {messageHandlers: new Proxy({}, {get: (_, name) => ({postMessage: value => messages.push({name, value})})})};
  w.setInterval = fn => { intervals.push(fn); return intervals.length; };
  w.setTimeout = () => 1;
  Object.defineProperty(w.document, 'readyState', {value: 'complete'});
  const video = w.document.querySelector('video');
  let paused = true, plays = 0;
  for (const video of w.document.querySelectorAll('video')) {
    Object.defineProperties(video, {
      paused: {get: () => paused}, duration: {get: () => 180}, readyState: {get: () => 4}
    });
    video.play = () => { paused = false; plays++; return Promise.resolve(); };
    video.pause = () => { paused = true; };
  }
  setup(w);
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

// Advertising before the content must never become the native movie or trigger auto-next.
const adFirst = fixture('<body><aside class="advertisement"><video src="https://cdn.example/promo.mp4"></video></aside><div id="player"><video src="https://cdn.example/feature.mp4"></video></div></body>');
assert(!adFirst.messages.some(m => m.name === 'videoFound' && m.value.url.includes('promo')));
assert(adFirst.messages.some(m => m.name === 'videoFound' && m.value.url.endsWith('/feature.mp4')));
adFirst.dom.window.close();

const onlyAd = fixture('<body><div class="video-ad"><video src="https://cdn.example/promo.mp4"></video></div><div id="player"></div></body>');
assert(!onlyAd.messages.some(m => m.name === 'videoFound' || m.name === 'mediaState'));
onlyAd.dom.window.close();

const streamAd = fixture('<body><video src="blob:https://example.com/video"></video></body>');
const req = new streamAd.w.XMLHttpRequest();
req.open('GET', 'https://cdn.example/preroll.m3u8');
streamAd.w.__anyanimeFocusPlayer();
assert(!streamAd.messages.some(m => m.name === 'videoFound'), 'An unrelated requested HLS manifest must never be assumed to be the blob video');
streamAd.dom.window.close();

const jw = fixture('<body><div id="player" class="jwplayer"><video src="https://cdn.example/pre.mp4"></video></div></body>', w => {
  const events = {};
  w.jwplayer = () => api;
  const api = {getPlaylistItem: () => ({sources: [{file:'https://cdn.example/actual-feature.m3u8'}]}), on: (event, fn) => {events[event] = fn;}};
  w.jwEvents = events;
});
assert(!jw.messages.some(m => m.name === 'videoFound' && m.value.url.endsWith('/pre.mp4')), 'Same-element JW preroll cannot be captured as movie');
assert(jw.messages.some(m => m.name === 'videoFound' && m.value.url.endsWith('/actual-feature.m3u8')));
jw.w.jwEvents.adPlay();
const beforeAdState = jw.messages.filter(m => m.name === 'mediaState').length;
jw.video.dispatchEvent(new jw.w.Event('ended'));
assert.equal(jw.messages.filter(m => m.name === 'mediaState').length, beforeAdState, 'Ad ended does not advance the app episode');
jw.w.jwEvents.adComplete();
jw.video.setAttribute('src','https://cdn.example/actual-feature.m3u8');
jw.w.__anyanimeFocusPlayer();
assert(jw.messages.filter(m => m.name === 'mediaState').length > beforeAdState, 'Movie state resumes after preroll');
jw.dom.window.close();
console.log('PASS: ad-before-movie, same-element JW preroll, ad end isolation and unrelated HLS rejection');
const verify = fixture('<title>StreamC</title><body><div id="player"></div><div id="verification"><button>Verify</button></div></body>');
assert.equal(verify.w.__anyanimeFocusPlayer(),false, 'An empty player must not hide StreamC verification before the film loads');
assert.notEqual(verify.w.document.querySelector('#verification').style.display, 'none');
verify.dom.window.close();

// NguonC/JW can start the ad before creating a movie video element.
const configuredDuringAd = fixture('<body><div class="jwplayer jw-flag-ads"><video src="https://cdn.example/promo.mp4"></video></div></body>', w => {
  w.jwplayer = () => ({getPlaylistItem: () => ({file: 'https://content.example/film.m3u8'}), on: () => {}});
});
assert(configuredDuringAd.messages.some(m => m.name === 'videoFound' && m.value.url === 'https://content.example/film.m3u8'), 'Resolve the configured movie immediately, while preroll is active');
assert(!configuredDuringAd.messages.some(m => m.name === 'videoFound' && m.value.url.endsWith('promo.mp4')));
configuredDuringAd.dom.window.close();
const configuredBeforeVideo = fixture('<body><div class="jwplayer" id="player"></div></body>', w => {
  w.jwplayer = () => ({getPlaylistItem: () => ({sources: [{file: 'https://content.example/real.m3u8'}]}), on: () => {}});
});
assert(configuredBeforeVideo.messages.some(m => m.name === 'videoFound' && m.value.url === 'https://content.example/real.m3u8'));
configuredBeforeVideo.dom.window.close();
console.log('PASS: configured movie handoff during preroll and before video creation');
const streamCDom = new JSDOM('<html><body><div id="player"></div></body></html>', {url:'https://embed11.streamc.xyz/embed.php?hash=test', runScripts:'outside-only'});
const sc = streamCDom.window;
sc.setInterval=()=>1; sc.setTimeout=()=>1;
let configured;
const originalLoader = function SealedLoader() {};
const scAPI = {setup: value => {configured=value; return scAPI;}, getPlaylistItem:()=>({file:'https://content.example/sealed.m3u8'}),on:()=>{}};
sc.eval(script);
sc.jwplayer=()=>scAPI;
sc.jwplayer.key='fixture-license';
sc.jwplayer('player').setup({file:'https://content.example/sealed.m3u8',advertising:{schedule:[{offset:'pre'}]},autostart:false,hlsjsConfig:{pLoader:originalLoader}});
assert.equal(configured.advertising,undefined,'StreamC ad configuration is removed before setup');
assert.equal(configured.autostart,true,'The movie starts automatically');
assert.equal(configured.hlsjsConfig.pLoader,originalLoader,'Keep the site decoder for sealed playlists');
assert.equal(sc.jwplayer.key,'fixture-license','JW license and static properties survive wrapping');
let scMessages=[];
sc.webkit={messageHandlers:new Proxy({},{get:(_,name)=>({postMessage:value=>scMessages.push({name,value})})})};
sc.streamAccess={shouldUseSealedLoader:()=>true};
sc.__anyanimeFocusPlayer();
assert(!scMessages.some(m=>m.name==='videoFound'),'A sealed playlist cannot be handed to a decoder that does not understand it');
streamCDom.window.close();
console.log('PASS: StreamC ad-free autoplay preserves the sealed decoder and license');

const trackFixture = fixture('<body><div class="jwplayer"><video src="blob:movie"></video><div class="jw-captions">Caption</div></div></body>', w => {
  let audio=0,caption=1;
  w.jwplayer=()=>({getPlaylistItem:()=>({file:'https://cdn.example/movie.m3u8'}),getAudioTracks:()=>[{name:'English'},{name:'Vietnamese'}],getCurrentAudioTrack:()=>audio,setCurrentAudioTrack:i=>audio=i,
    getCaptionsList:()=>[{label:'Off'},{label:'English'},{label:'Vietnamese'}],getCurrentCaptions:()=>caption,setCurrentCaptions:i=>caption=i,setCaptions:()=>{}});
});
function selectTrack(kind,id){trackFixture.w.dispatchEvent(new trackFixture.w.MessageEvent('message',{data:{type:'AnPinimeCommand',name:'track',kind,id}}));}
selectTrack('audio','1');selectTrack('subtitles','2');
let tracks=trackFixture.messages.filter(m=>m.name==='mediaState').at(-1).value.tracks;
assert.equal(tracks.audio.length,2);assert.equal(tracks.audioID,'1');assert.equal(tracks.subtitleID,'2');
selectTrack('subtitles','off');assert.equal(trackFixture.messages.filter(m=>m.name==='mediaState').at(-1).value.tracks.subtitleID,'off');
assert.notEqual(trackFixture.w.document.querySelector('.jw-captions').style.display,'none');
trackFixture.command('rate',3);assert.equal(trackFixture.video.playbackRate,3);
trackFixture.dom.window.close();
console.log('PASS: actual JW audio/caption selection, off, caption visibility and 3x speed');
