import {CONFIG} from './config.js';
import {World} from './world.js';

const world=new World(CONFIG);

const demoImages=Array.from({length:20},(_,i)=>({
imageDefinitionID:`demo_${i}`,
label:`Image ${i+1}`
}));

world.initializeBoard(demoImages);

console.log('World initialized');
console.log(world);

document.body.insertAdjacentHTML(
'beforeend',
`<pre>${JSON.stringify(world.positions,null,2)}</pre>`
);
