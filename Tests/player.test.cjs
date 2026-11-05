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
      paused: {get: () => paused}, duration: {get: () => 180}, readyState: {get: () => 4, configurable: true},
      videoWidth: {get: () => 640}, videoHeight: {get: () => 360}
    });
    video.play = () => { paused = false; plays++; return Promise.resolve(); };
    video.pause = () => { paused = true; };
  }
  setup(w);
  w.eval(script);
  return {dom, w, messages, video, intervals, get plays(){return plays;},
    command(name, value = 0, extra = {}) { w.dispatchEvent(new w.MessageEvent('message', {data:{type:'AnPinimeCommand', name, value, ...extra}})); }};
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
assert(f.messages.some(m => m.name === 'videoFound' && m.value.provenance === 'media'), 'An actual decoded HTTP video is distinguished from a configured playlist');
assert(f.messages.some(m => m.name === 'mediaState' && m.value.videoWidth === 640 && m.value.videoHeight === 360), 'Web playback reports actual decoded video dimensions');
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
assert(jw.messages.some(m => m.name === 'videoFound' && m.value.url.endsWith('/actual-feature.m3u8') && m.value.provenance === 'media'), 'An initial playlist hint can upgrade only after that exact HTTP source supplies a decoded frame');
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

const lowReady = fixture('<div id="player"><video src="https://cdn.example/movie.mp4"></video></div>', w => {
  Object.defineProperty(w.document.querySelector('video'), 'readyState', {get: () => 2});
  w.Date.now = () => 1000;
});
lowReady.video.currentTime = 12;
lowReady.intervals.forEach(fn => fn());
assert(lowReady.messages.some(m => m.name === 'mediaState' && m.value.time === 12 && !m.value.buffering));
lowReady.w.Date.now = () => 4000;
lowReady.intervals.forEach(fn => fn());
assert(lowReady.messages.filter(m => m.name === 'mediaState').at(-1).value.buffering, 'A real stall still reports buffering');
lowReady.command('pause');
assert(!lowReady.messages.filter(m => m.name === 'mediaState').at(-1).value.buffering, 'User pause does not leave a buffering spinner');
lowReady.dom.window.close();
const pauseOverlay = fixture('<div class="jwplayer"><video src="https://cdn.example/movie.mp4"></video><div class="jw-overlays"><div class="mixed-overlay"><div class="jw-captions">Subtitle</div><div id="unmarked-buttons"><button>Đóng quảng cáo</button><button>Đóng và xem tiếp</button></div></div><div class="pause-ad"><button>Ad</button></div></div></div>');
pauseOverlay.command('pause'); pauseOverlay.w.__anyanimeFocusPlayer();
assert.equal(pauseOverlay.w.document.querySelector('.pause-ad').style.display, 'none');
assert.equal(pauseOverlay.w.document.querySelector('#unmarked-buttons').style.display, 'none', 'Pause ad controls are hidden even when their wrapper shares captions and has no ad class');
assert.notEqual(pauseOverlay.w.document.querySelector('.jw-captions').style.display, 'none');
pauseOverlay.dom.window.close();

const webPiP = fixture('<div id="player"><video src="blob:movie"></video></div>', w => {
  const v = w.document.querySelector('video');
  w.presentationCalls = [];
  v.webkitSupportsPresentationMode = mode => mode === 'picture-in-picture';
  v.webkitSetPresentationMode = mode => { w.presentationCalls.push(mode); v.webkitPresentationMode = mode; };
});
assert(webPiP.messages.some(m => m.name === 'mediaState' && m.value.pipSupported));
webPiP.command('pipAutomatically');
assert.equal(webPiP.w.presentationCalls.length, 0, 'Automatic requests wait for the app preference');
webPiP.command('automaticPiP', 1);
webPiP.command('pipAutomatically');
assert.equal(webPiP.video.webkitPresentationMode, 'picture-in-picture', 'An enabled background request reaches the actual video');
webPiP.command('pipStop');
webPiP.w.presentationCalls.length = 0;
webPiP.command('automaticPiP', 0);
webPiP.command('pipAutomatically');
assert.equal(webPiP.w.presentationCalls.length, 0, 'Turning automatic PiP off blocks background requests');
Object.defineProperty(webPiP.w.document, 'hidden', {value: true});
webPiP.w.document.dispatchEvent(new webPiP.w.Event('visibilitychange'));
assert.equal(webPiP.w.presentationCalls.length, 0, 'Document visibility alone cannot force a presentation transition');
webPiP.command('pip');
assert.equal(webPiP.video.webkitPresentationMode, 'picture-in-picture', 'The native PiP command reaches the actual WebKit video');
webPiP.command('pip');
assert.equal(webPiP.w.presentationCalls.length, 1, 'Repeated background/manual commands cannot start a second PiP presentation');
webPiP.video.style.width = '40px';
webPiP.video.setAttribute('src', 'https://cdn.example/late-native.mp4');
webPiP.w.__anyanimeFocusPlayer();
assert.equal(webPiP.video.style.width, '40px', 'The page does not resize or reparent the PiP video');
assert(!webPiP.messages.some(m => m.name === 'videoFound'), 'A website video in PiP cannot switch to a second native owner');
webPiP.command('pipStop');
assert.equal(webPiP.video.webkitPresentationMode, 'inline', 'Closing the player can release WebKit PiP');
webPiP.command('pause'); webPiP.command('pip');
assert.equal(webPiP.video.webkitPresentationMode, 'inline', 'Paused videos do not automatically open PiP');
webPiP.command('play');
webPiP.w.document.dispatchEvent(new webPiP.w.Event('visibilitychange'));
assert.equal(webPiP.video.webkitPresentationMode, 'inline', 'Visibility changes after playback resumes still do not force PiP');
webPiP.video.webkitSupportsPresentationMode = () => false;
webPiP.w.__anyanimeFocusPlayer();
assert(!webPiP.messages.filter(m => m.name === 'mediaState').at(-1).value.pipSupported, 'An unsupported API does not advertise usable PiP');
webPiP.dom.window.close();
const pendingPiP = fixture('<video src="blob:movie"></video>', w => {
  w.Date.now = () => 1000; w.requests = 0;
  const v = w.document.querySelector('video');
  v.webkitSupportsPresentationMode = () => true;
  v.webkitSetPresentationMode = () => { w.requests++; };
});
pendingPiP.command('pip'); pendingPiP.command('pip');
assert.equal(pendingPiP.w.requests, 1, 'An asynchronous WebKit PiP request is coalesced');
assert(pendingPiP.messages.filter(m => m.name === 'mediaState').at(-1).value.pipPending);
pendingPiP.video.style.width = '40px';
const originalParent = pendingPiP.video.parentElement;
pendingPiP.w.__anyanimeFocusPlayer();
assert.equal(pendingPiP.video.style.width, '40px', 'The page does not resize a video while WebKit PiP is starting');
assert.equal(pendingPiP.video.parentElement, originalParent, 'The PiP transition keeps the same inline container');
pendingPiP.w.Date.now = () => 3000;
pendingPiP.w.__anyanimeFocusPlayer();
assert.equal(pendingPiP.video.style.width, '100vw', 'Inline layout resumes after a failed PiP request expires');
pendingPiP.command('pip');
assert.equal(pendingPiP.w.requests, 2, 'A failed request can be retried after its bounded pending interval');
pendingPiP.command('pipStop');
assert(!pendingPiP.messages.filter(m => m.name === 'mediaState').at(-1).value.pipPending);
pendingPiP.video.style.width = '40px';
pendingPiP.w.__anyanimeFocusPlayer();
assert.equal(pendingPiP.video.style.width, '100vw', 'Stopping a pending PiP request restores ordinary inline layout');
pendingPiP.dom.window.close();
for (const enabled of [true, false]) {
  const delayedVideo = fixture('<div id="player"></div>');
  assert(delayedVideo.messages.some(m => m.name === 'playerReady'), 'The empty container can report readiness before a video exists');
  delayedVideo.command('automaticPiP', enabled ? 1 : 0);
  const v = delayedVideo.w.document.createElement('video');
  v.src = 'blob:late-movie';
  Object.defineProperties(v, {
    paused: {get: () => false}, duration: {get: () => 180}, readyState: {get: () => 4},
    videoWidth: {get: () => 640}, videoHeight: {get: () => 360}
  });
  let presentations = 0;
  v.webkitSupportsPresentationMode = () => true;
  v.webkitSetPresentationMode = () => { presentations++; };
  delayedVideo.w.document.querySelector('#player').appendChild(v);
  delayedVideo.w.__anyanimeFocusPlayer();
  assert.equal(presentations, 0, 'Retaining the preference never forces a PiP start');
  const lateSession = delayedVideo.messages.filter(m => m.name === 'mediaState').at(-1).value.pipSessionID;
  assert.equal(typeof lateSession, 'string', 'A late-created video reports a usable native session ID');
  delayedVideo.command('pipAutomatically', 0, {sessionID:lateSession, requestID:'late-native-request'});
  assert.equal(presentations, enabled ? 1 : 0, 'A video created after readiness applies the retained preference to an actual background request');
  delayedVideo.dom.window.close();
}
console.log('PASS: WebKit PiP single ownership, actual commands, preference, pause, pending retry and inline layout');
(async () => {
  const manifest = '#EXTM3U\n#EXT-X-TARGETDURATION:60\n#EXTINF:60,\na.ts\n#EXTINF:60,\nb.ts\n#EXTINF:60,\nc.ts\n#EXT-X-ENDLIST';
  const blob = fixture('<div id="player"><video src="blob:https://animevietsub.example/movie"></video></div>', w => {
    w.fetch = async () => ({url:'https://cdn.example/episode.m3u8',headers:{get:()=> 'application/vnd.apple.mpegurl'},clone:()=>({text:async()=>manifest})});
    w.originalFetch = w.fetch;
  });
  assert.equal(blob.w.fetch, blob.w.originalFetch, 'The app does not replace the website fetch/decoder pipeline');
  await blob.w.fetch('https://cdn.example/episode.m3u8');
  await Promise.resolve(); await Promise.resolve();
  blob.intervals.forEach(fn => fn());
  assert(!blob.messages.some(m => m.name === 'videoFound'), 'Even a duration-matched manifest is not proof that a blob can play outside its website decoder');
  assert(!blob.video.paused && blob.plays === 1, 'The original website playback remains running');
  blob.dom.window.close();
  const wrongManifest = fixture('<div id="player"><video src="blob:https://animevietsub.example/movie"></video></div>', w => {
    w.fetch = async () => ({url:'https://cdn.example/unrelated.m3u8',headers:{get:()=> 'application/vnd.apple.mpegurl'},clone:()=>({text:async()=>manifest.replace(/#EXTINF:60/g, '#EXTINF:20')})});
  });
  await wrongManifest.w.fetch('https://cdn.example/unrelated.m3u8');
  await Promise.resolve(); await Promise.resolve();
  wrongManifest.intervals.forEach(fn => fn());
  assert(!wrongManifest.messages.some(m => m.name === 'videoFound'), 'An unrelated VOD with a different duration cannot replace the active video');
  wrongManifest.dom.window.close();
  console.log('PASS: progressing readyState=2, pause-ad isolation, decoder preservation and no speculative blob handoff');
})().catch(error => { console.error(error); process.exitCode = 1; });


// Match the Swift bridge payloads: session and request IDs are protocol data,
// not an assertion that the real iOS presentation API succeeds.
const bridge = fixture('<video src="blob:bridge-first"></video>', w => {
  const v = w.document.querySelector('video');
  w.Date.now = () => 1000;
  w.presentationCalls = [];
  v.webkitSupportsPresentationMode = () => true;
  v.webkitSetPresentationMode = mode => { w.presentationCalls.push(mode); };
});
const lastState = f => f.messages.filter(m => m.name === 'mediaState').at(-1).value;
const notices = f => f.messages.filter(m => m.name === 'pipState').map(m => m.value);
const spontaneous = fixture('<video src="blob:system-pip"></video>', w => {
  const v = w.document.querySelector('video');
  v.webkitSupportsPresentationMode = () => true;
  v.webkitSetPresentationMode = () => {};
});
const spontaneousSession = lastState(spontaneous).pipSessionID;
spontaneous.video.webkitPresentationMode = 'picture-in-picture';
spontaneous.video.dispatchEvent(new spontaneous.w.Event('webkitpresentationmodechanged'));
assert.equal(lastState(spontaneous).pipActive, true);
assert.equal(lastState(spontaneous).pipRequestID, '', 'System-initiated PiP has no invented native request ID');
assert.deepEqual({...notices(spontaneous).at(-1)}, {sessionID:spontaneousSession, requestID:'', status:'active', error:''});
spontaneous.video.webkitPresentationMode = 'inline';
spontaneous.video.dispatchEvent(new spontaneous.w.Event('webkitpresentationmodechanged'));
assert.equal(lastState(spontaneous).pipActive, false);
assert.deepEqual({...notices(spontaneous).at(-1)}, {sessionID:spontaneousSession, requestID:'', status:'stopped', error:''},
  'System-initiated PiP reports the same empty request identity when returning inline');
spontaneous.dom.window.close();
let sid = lastState(bridge).pipSessionID;
assert.equal(typeof sid, 'string'); assert(sid.length > 0);
bridge.command('pip', 0, {sessionID:sid, requestID:'native-1'});
assert.equal(lastState(bridge).pipRequestID, 'native-1');
assert.equal(lastState(bridge).pipPending, true);
assert(notices(bridge).some(x => x.sessionID === sid && x.requestID === 'native-1' && x.status === 'pending'));
bridge.command('pip', 0, {sessionID:sid, requestID:'duplicate'});
assert.equal(bridge.w.presentationCalls.length, 1);
assert.equal(lastState(bridge).pipRequestID, 'native-1', 'Coalescing preserves the owner request ID');
bridge.video.webkitPresentationMode = 'picture-in-picture';
bridge.video.dispatchEvent(new bridge.w.Event('webkitpresentationmodechanged'));
assert(notices(bridge).some(x => x.sessionID === sid && x.requestID === 'native-1' && x.status === 'active'));
assert.equal(lastState(bridge).pipPending, false);
bridge.video.webkitPresentationMode = 'inline';
bridge.video.setAttribute('src', 'blob:changed-at-inline-return');
bridge.video.dispatchEvent(new bridge.w.Event('webkitpresentationmodechanged'));
assert.equal(notices(bridge).at(-1).status, 'stopped');
assert.equal(notices(bridge).at(-1).sessionID, sid, 'Source changes while returning inline first close the old active session');
assert.equal(lastState(bridge).pipActive, false);
bridge.w.__anyanimeFocusPlayer();
sid = lastState(bridge).pipSessionID;
bridge.command('automaticPiP', 0);
bridge.command('pipAutomatically', 0, {sessionID:sid, requestID:'native-disabled'});
assert.equal(notices(bridge).at(-1).error, 'automatic-disabled');
assert.equal(lastState(bridge).pipPending, false);
bridge.command('pip', 0, {sessionID:sid, requestID:'native-timeout'});
bridge.w.Date.now = () => 2600;
bridge.w.__anyanimeFocusPlayer();
assert(notices(bridge).some(x => x.requestID === 'native-timeout' && x.status === 'error' && x.error === 'timeout'));
assert.equal(lastState(bridge).pipPending, false);
bridge.command('pause');
bridge.command('pip', 0, {sessionID:sid, requestID:'native-paused'});
assert.equal(notices(bridge).at(-1).error, 'paused');
bridge.dom.window.close();

const rejected = fixture('<video src="blob:promise-first"></video>', w => {
  w.Date.now = () => 1000;
  Object.defineProperty(w.document, 'pictureInPictureEnabled', {value:true});
  const v = w.document.querySelector('video');
  w.pendingRequests = [];
  v.requestPictureInPicture = () => ({then(resolve, reject) { w.pendingRequests.push({resolve, reject}); }});
});
const oldSession = lastState(rejected).pipSessionID;
rejected.command('pip', 0, {sessionID:oldSession, requestID:'rejected-1'});
rejected.w.pendingRequests[0].reject(new Error('Denied'));
assert.equal(lastState(rejected).pipPending, false);
assert.equal(notices(rejected).at(-1).error, 'rejected');
rejected.command('pip', 0, {sessionID:oldSession, requestID:'old-late'});
rejected.w.Date.now = () => 3000;
rejected.w.__anyanimeFocusPlayer();
rejected.video.setAttribute('src', 'blob:promise-next');
rejected.w.__anyanimeFocusPlayer();
const newSession = lastState(rejected).pipSessionID;
assert.notEqual(newSession, oldSession, 'A new inline media source gets a fresh session');
const noticesBeforeMismatch = notices(rejected).length;
rejected.command('pip', 0, {sessionID:oldSession, requestID:'wrong-session'});
assert.equal(rejected.w.pendingRequests.length, 2, 'A stale native session cannot call presentation APIs');
assert.equal(notices(rejected).length, noticesBeforeMismatch, 'A broadcast to the wrong frame cannot emit another session\'s terminal notice');
rejected.command('pip', 0, {sessionID:newSession, requestID:'current-request'});
const noticesWhilePending = notices(rejected).length;
rejected.command('pip', 0, {sessionID:oldSession, requestID:'current-request'});
assert.equal(notices(rejected).length, noticesWhilePending, 'A mismatching session cannot acknowledge the currently pending native request ID');
assert.equal(lastState(rejected).pipPending, true);
rejected.w.pendingRequests[1].reject(new Error('Late prior rejection'));
assert.equal(lastState(rejected).pipRequestID, 'current-request');
assert.equal(lastState(rejected).pipPending, true, 'A stale rejection cannot clear the newer request');
rejected.w.document.pictureInPictureElement = rejected.video;
rejected.video.dispatchEvent(new rejected.w.Event('enterpictureinpicture'));
assert.equal(notices(rejected).at(-1).requestID, 'current-request');
assert.equal(notices(rejected).at(-1).status, 'active');
rejected.w.pendingRequests[1].resolve();
assert.equal(lastState(rejected).pipActive, true);
rejected.w.document.pictureInPictureElement = null;
rejected.video.dispatchEvent(new rejected.w.Event('leavepictureinpicture'));
assert.equal(notices(rejected).at(-1).status, 'stopped');
assert.equal(lastState(rejected).pipActive, false);
const replacement = rejected.video.cloneNode(true);
Object.defineProperties(replacement, {
  paused:{get:()=>false},duration:{get:()=>180},readyState:{get:()=>4},
  videoWidth:{get:()=>640},videoHeight:{get:()=>360}
});
replacement.play = () => Promise.resolve();
let replacementRequests = 0;
replacement.webkitSupportsPresentationMode = () => true;
replacement.webkitSetPresentationMode = () => { replacementRequests++; };
rejected.video.replaceWith(replacement);
rejected.w.__anyanimeFocusPlayer();
const replacementSession = lastState(rejected).pipSessionID;
assert.notEqual(replacementSession, newSession, 'A replacement video has a distinct session even for the same URL');
rejected.command('pip', 0, {sessionID:newSession, requestID:'old-element-command'});
assert.equal(replacementRequests, 0);
rejected.w.pendingRequests[2].reject(new Error('Old element late rejection'));
assert.equal(lastState(rejected).pipSessionID, replacementSession);
assert.equal(lastState(rejected).pipPending, false);
rejected.command('pip', 0, {sessionID:replacementSession, requestID:'replacement-command'});
assert.equal(replacementRequests, 1);
assert.equal(lastState(rejected).pipRequestID, 'replacement-command');
rejected.dom.window.close();
console.log('PASS: Swift/WebKit PiP session/request protocol, native payloads, presentation events, timeout/retry, rejection and stale-completion isolation');

// The modal shape and original button side effects match the public reconstructed
// AVS v1.3.1 init_final.js at 38c9e7d640c1487df55bce79a0db20ef4783b652.
// This is a deterministic page fixture, not evidence of live-site playback.
function animeResumePrompt(f, renamed = false) {
  const w = f.w, overlay = w.document.createElement('div');
  overlay.id = renamed ? 'changed-resume-dialog' : 'avs-resume-overlay';
  overlay.innerHTML = '<div id="avs-resume-box"><div>Hệ thống ghi nhận bạn đã từng xem anime này trước đó! Bạn có muốn xem tiếp từ đoạn:</div>' +
    '<button id="avs-resume-btn-yes">Xem tiếp</button><button id="avs-resume-btn-no">Từ đầu</button></div>';
  const yes = overlay.querySelector('#avs-resume-btn-yes'), no = overlay.querySelector('#avs-resume-btn-no');
  if (renamed) { yes.removeAttribute('id'); no.removeAttribute('id'); no.textContent = 'TỪ ĐẦU'; }
  const clicks = {yes:0, no:0};
  yes.onclick = () => { clicks.yes++; f.video.currentTime = 93; overlay.remove(); };
  no.onclick = () => { clicks.no++; w.localStorage.removeItem('resumevideodata-selected'); overlay.remove(); };
  w.document.querySelector('.jw-wrapper').appendChild(overlay);
  return {overlay, clicks};
}

(async () => {
  const flushDOM = () => new Promise(resolve => setImmediate(resolve));
  const animeHTML = '<div class="jwplayer"><div class="jw-wrapper"><video src="blob:anime-episode"></video></div></div>';
  const anime = fixture(animeHTML, w => {
    w.__anpinimeAnimePlayback = {episodeID:'anime:selected-episode', initialPosition:0};
    const v = w.document.querySelector('video');
    v.currentTime = 81;
    Object.defineProperty(v, 'readyState', {get:()=>0, configurable:true});
    v.webkitSupportsPresentationMode = () => true;
    v.webkitSetPresentationMode = mode => { v.webkitPresentationMode = mode; };
    w.localStorage.setItem('resumevideodata-selected', '93:180');
    w.localStorage.setItem('resumevideodata-other', '67:180');
    w.localStorage.setItem('unrelated-setting', 'keep');
    w.sessionStorage.setItem('avs_resume_selected', '48');
  });
  assert.equal(anime.video.currentTime, 81, 'Initialization waits until media can seek');
  Object.defineProperty(anime.video, 'readyState', {get:()=>4, configurable:true});
  anime.video.dispatchEvent(new anime.w.Event('loadedmetadata'));
  assert.equal(anime.video.currentTime, 0, 'A newly selected anime starts at zero once metadata arrives');
  assert.equal(lastState(anime).time, 0, 'Native receives the initialized anime time');
  anime.video.currentTime = 12;
  anime.video.dispatchEvent(new anime.w.Event('timeupdate'));
  anime.w.__anyanimeFocusPlayer();
  assert.equal(anime.video.currentTime, 12, 'Normal playback and repeated focus do not restart the episode');
  const popup = animeResumePrompt(anime);
  await flushDOM();
  assert.deepEqual(popup.clicks, {yes:0, no:1}, 'Late DOM selects the original From Beginning action without tapping Continue');
  assert.equal(popup.overlay.isConnected, false, 'The website action releases its blocking overlay');
  assert.equal(anime.w.localStorage.getItem('resumevideodata-selected'), null, 'The original handler removes its exact selected-media key');
  assert.equal(anime.w.localStorage.getItem('resumevideodata-other'), '67:180');
  assert.equal(anime.w.localStorage.getItem('unrelated-setting'), 'keep');
  assert.equal(anime.w.sessionStorage.getItem('avs_resume_selected'), '48', 'Token-renewal recovery storage is preserved');
  assert.equal(anime.video.currentTime, 12, 'A late prompt cannot rewind already initialized playback');
  anime.command('seek', 48); anime.command('pause');
  anime.video.dispatchEvent(new anime.w.Event('loadedmetadata'));
  const afterSeek = animeResumePrompt(anime, true);
  await flushDOM();
  assert.deepEqual(afterSeek.clicks, {yes:0, no:1}, 'Known resume wording still resolves a changed modal layout');
  assert.equal(anime.video.currentTime, 48);
  assert.equal(anime.video.paused, true, 'Prompt resolution and metadata retain explicit pause intent');
  anime.command('play');
  anime.command('pip', 0, {sessionID:lastState(anime).pipSessionID, requestID:'anime-resume-pip'});
  anime.video.dispatchEvent(new anime.w.Event('webkitpresentationmodechanged'));
  anime.video.currentTime = 56;
  anime.command('pipStop');
  anime.w.__anyanimeFocusPlayer();
  assert.equal(anime.video.currentTime, 56, 'PiP return retains this viewing session');
  anime.command('seek', 72); anime.command('play');
  anime.w.__anyanimeFocusPlayer();
  assert.equal(anime.video.currentTime, 72, 'Native-failure restoration seek is not overridden by focus');
  assert.equal(anime.video.paused, false);
  const afterRecovery = animeResumePrompt(anime);
  await flushDOM();
  assert.deepEqual(afterRecovery.clicks, {yes:0, no:1});
  assert.equal(anime.video.currentTime, 72, 'A late prompt after PiP/native recovery preserves the same-session position');
  const unrelated = anime.w.document.createElement('div');
  unrelated.innerHTML = '<p>Chọn chương</p><button>Từ đầu</button>';
  let unrelatedClicks = 0;
  unrelated.querySelector('button').onclick = () => { unrelatedClicks++; };
  anime.w.document.querySelector('.jw-wrapper').appendChild(unrelated);
  await flushDOM();
  assert.equal(unrelatedClicks, 0, 'A From Beginning label outside the known resume prompt is not activated');
  assert.equal(unrelated.isConnected, true);
  anime.video.setAttribute('src', 'blob:refreshed-same-episode');
  anime.video.dispatchEvent(new anime.w.Event('loadedmetadata'));
  assert.equal(anime.video.currentTime, 72, 'Refreshing a source within the episode does not reinitialize its position');
  anime.dom.window.close();

  const recovered = fixture(animeHTML, w => {
    w.__anpinimeAnimePlayback = {episodeID:'anime:same-session-recovery', initialPosition:44};
    w.document.querySelector('video').currentTime = 93;
  });
  assert.equal(recovered.video.currentTime, 44, 'A recreated website can honor native-failure same-session position');
  recovered.command('seek', 66); recovered.w.__anyanimeFocusPlayer();
  assert.equal(recovered.video.currentTime, 66);
  recovered.dom.window.close();

  const earlySeek = fixture(animeHTML, w => {
    w.__anpinimeAnimePlayback = {episodeID:'anime:early-seek', initialPosition:0};
    Object.defineProperty(w.document.querySelector('video'), 'readyState', {get:()=>0, configurable:true});
  });
  earlySeek.command('seek', 32);
  Object.defineProperty(earlySeek.video, 'readyState', {get:()=>4});
  earlySeek.video.dispatchEvent(new earlySeek.w.Event('loadedmetadata'));
  assert.equal(earlySeek.video.currentTime, 32, 'An explicit seek before metadata wins over automatic initialization');
  earlySeek.dom.window.close();

  const nextEpisode = fixture(animeHTML, w => {
    w.__anpinimeAnimePlayback = {episodeID:'anime:next-episode', initialPosition:0};
    w.document.querySelector('video').currentTime = 91;
  });
  assert.equal(nextEpisode.video.currentTime, 0, 'Opening another episode initializes its independent playback');
  nextEpisode.dom.window.close();

  const movie = fixture(animeHTML, w => { w.document.querySelector('video').currentTime = 87; });
  const moviePopup = animeResumePrompt(movie);
  await flushDOM();
  assert.equal(movie.video.currentTime, 87, 'Movie providers do not receive anime startup resets');
  assert.deepEqual(moviePopup.clicks, {yes:0, no:0}, 'Anime prompt handling is inactive without native anime context');
  movie.dom.window.close();
  console.log('PASS: anime episode-scoped start, original late resume action, storage isolation, pause/seek and PiP/native recovery preservation');
})().catch(error => { console.error(error); process.exitCode = 1; });
