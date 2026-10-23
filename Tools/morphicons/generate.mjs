import {resampleIcon, buildPlan, allocOutputs, interpPolar, Spring, SPRING_PRESETS} from 'morphicons';
import {writeFileSync, mkdirSync} from 'node:fs';

// App-owned 24-unit stroke icons. Morphicons supplies correspondence and motion.
const icons = {
  play: 'M8 5 L20 12 L8 19 Z', pause: 'M8 5 L8 19 M16 5 L16 19',
  lock: 'M6 10 L18 10 L18 21 L6 21 Z M8 10 L8 7 C8 1 16 1 16 7 L16 10 M12 14 L12 17',
  unlock: 'M6 10 L18 10 L18 21 L6 21 Z M8 10 L8 7 C8 1 16 1 16 7 M12 14 L12 17',
  expand: 'M4 9 L4 4 L9 4 M15 4 L20 4 L20 9 M20 15 L20 20 L15 20 M9 20 L4 20 L4 15',
  shrink: 'M4 9 L9 9 L9 4 M15 4 L15 9 L20 9 M20 15 L15 15 L15 20 M9 20 L9 15 L4 15',
  menu: 'M4 6 L20 6 M4 12 L20 12 M4 18 L20 18', close: 'M6 6 L18 18 M6 18 L18 6',
  back: 'M15 5 L8 12 L15 19', down: 'M5 8 L12 15 L19 8',
  next: 'M5 5 L15 12 L5 19 Z M19 5 L19 19',
  episodes: 'M4 8 L20 8 L20 21 L4 21 Z M6 4 L18 4 M8 1 L16 1',
  settings: 'M4 6 L9 6 M15 6 L20 6 M4 12 L14 12 M20 12 L20 12 M4 18 L5 18 M11 18 L20 18 M12 3 L12 9 M17 9 L17 15 M8 15 L8 21',
  captions: 'M3 5 L21 5 L21 19 L3 19 Z M10 9 C5 7 5 17 10 15 M18 9 C13 7 13 17 18 15',
  quality: 'M3 5 L21 5 L21 17 L3 17 Z M8 21 L16 21 M12 17 L12 21',
  audio: 'M4 10 L8 10 L13 5 L13 19 L8 14 L4 14 Z M17 8 C21 10 21 14 17 16',
  reload: 'M20 10 C18 1 4 2 4 12 C4 21 17 23 20 16 M20 4 L20 10 L14 10',
  check: 'M4 12 L9 17 L20 6'
};
const round = xs => Array.from(xs, n => Math.round(n * 10000) / 10000);
const sampled = Object.fromEntries(Object.entries(icons).map(([key, path]) => [key,resampleIcon(path,32)]));
const output = {version:'morphicons@2.0.0', icons:{}, transitions:{}};
for (const [key, paths] of Object.entries(sampled)) output.icons[key] = paths.map(p => [...round(p.pts),...(p.closed?round(p.pts.slice(0,2)):[])]);
for (const [from,to] of [['play','pause'],['unlock','lock'],['expand','shrink'],['menu','close'],['settings','close'],['down','back']]) {
  for (const [a,b] of [[from,to],[to,from]]) {
    const plan=buildPlan(sampled[a],sampled[b]), buffers=allocOutputs(plan), spring=new Spring();
    spring.config(SPRING_PRESETS.smooth.k,SPRING_PRESETS.smooth.c); spring.start();
    const frames=[];
    for (let n=0;n<54;n++) {
      const done=n>0&&spring.step(1/60);
      interpPolar(plan,n===53?1:spring.x,buffers);
      frames.push(buffers.map(round));
      if(done)break;
    }
    interpPolar(plan,1,buffers); frames.push(buffers.map(round));
    output.transitions[`${a}:${b}`]=frames;
  }
}
const destination=new URL('../../AnyAnime/Resources/Morphicons.json',import.meta.url);
mkdirSync(new URL('../../AnyAnime/Resources/',import.meta.url),{recursive:true});
writeFileSync(destination,JSON.stringify(output));
console.log(`Generated ${Object.keys(icons).length} icons and ${Object.keys(output.transitions).length} Morphicons transitions`);
