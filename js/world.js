
function shuffle(array){
 const shuffled=[...array];
 for(let i=shuffled.length-1;i>0;i--){
   const j=Math.floor(Math.random()*(i+1));
   [shuffled[i],shuffled[j]]=[shuffled[j],shuffled[i]];
 }
 return shuffled;
}

class World{
 constructor(){this.positions=[];this.episodeScore=0;this.sessionScore=0;}
 startEpisode(images){
   this.episodeScore=0;
   this.positions=shuffle(images).map((img,i)=>({positionID:i,imageInstance:img,resolved:false}));
 }
 getPosition(id){return this.positions[id];}
 addReward(points){this.episodeScore+=points;}
 addSessionReward(points){this.sessionScore+=points;}
}
