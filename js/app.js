import {World} from './world.js';
import {Board} from './board.js';
import {Logger} from './logger.js';
import {CONFIG} from './config.js';

const logger=new Logger();
const world=new World(CONFIG);

const defs=['🦘','🐕','🐋','🐦','🐈','🪑','🚗','📘','🎸','🏠'];

const images=Array.from({length:20},(_,i)=>({
id:i,
label:defs[i%defs.length]
}));

world.startEpisode(images);

const board=new Board('board',positionID=>{
    logger.log('click',{positionID});
    console.log('Position',positionID,'clicked');
});

board.draw(world);

console.log('Logger',logger);
console.log('World',world);
