class RandomAgent{
 choose(world){
   const unresolvedPositions=world.positions.filter(p=>!p.resolved);
   if(!unresolvedPositions.length)return undefined;
   const index=Math.floor(Math.random()*unresolvedPositions.length);
   return unresolvedPositions[index].positionID;
 }
}
