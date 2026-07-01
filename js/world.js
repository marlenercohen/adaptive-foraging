export class World{
constructor(config){
this.config=config;
this.episodeScore=0;
this.sessionScore=0;
this.currentActor='human';
this.positions=[];
}
initializeBoard(imageInstances){
this.positions=imageInstances.map((img,i)=>({
positionID:i,
imageInstance:img,
resolved:false,
resolvedBy:null,
rewardGiven:false
}));
}
resolve(positionID,actor,reward){
const p=this.positions[positionID];
if(!p.resolved){
p.resolved=true;
p.resolvedBy=actor;
p.rewardGiven=reward;
}
}
isResolved(positionID){
return this.positions[positionID].resolved;
}
addPoints(n){
this.episodeScore+=n;
this.sessionScore+=n;
}
}
