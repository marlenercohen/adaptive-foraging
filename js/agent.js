class RandomAgent{
 choose(world){
   const unresolvedPositions=world.positions.filter(p=>!p.resolved);
   if(!unresolvedPositions.length)return undefined;
   const index=Math.floor(Math.random()*unresolvedPositions.length);
   return unresolvedPositions[index].positionID;
 }
}

class FeatureLearningAgent{
 constructor(options = {}){
   this.weights={};
   this.learningRate=0.1;
   const wmConfig = options.workingMemory || {};
   this.workingMemory = new ExponentialWorkingMemory(wmConfig);
   const configuredAlpha = Number(wmConfig.memorySuppressionAlpha);
   const configuredBeta = Number(wmConfig.memorySuppressionBeta);
   this.memorySuppressionAlpha = Number.isFinite(configuredAlpha) ? Math.max(configuredAlpha, 0) : 3.0;
   this.memorySuppressionBeta = Number.isFinite(configuredBeta) ? Math.max(configuredBeta, 0) : 2.0;
 }

 makeFeatureKey(feature,value){
   return `${feature}=${value}`;
 }

 ensureFeature(feature,value){
   const key=this.makeFeatureKey(feature,value);
   if(this.weights[key]===undefined){
     this.weights[key]=0;
   }
 }

 updateWeights(features,reward){
   const featureEntries=Object.entries(features || {});
   featureEntries.forEach(([feature,value])=>{
     this.ensureFeature(feature,value);
     const delta = reward ? this.learningRate : -this.learningRate;
     this.weights[this.makeFeatureKey(feature,value)] += delta;
   });
 }

 receiveFeedback(stimulus,features,reward){
   if(!stimulus){
     return;
   }
   this.updateWeights(features,reward);
   console.log('FeatureLearningAgent feedback', {
     stimulus: stimulus.id,
     features,
     reward,
     weights: {...this.weights}
   });
 }

 onEpisodeStart(){
   this.workingMemory.resetEpisode();
 }

 observeStimulusSelection(positionID){
   this.workingMemory.recordVisit(positionID);
 }

 getEffectiveStrength(positionID){
   return this.workingMemory.getStrength(positionID);
 }

 choose(world){
   const allPositions = world.positions || [];
   if(!allPositions.length)return undefined;

   const scored=allPositions.map(position=>{
     const features=position.imageInstance?.features || {};
     const featureScore=Object.entries(features).reduce((total,[feature,value])=>{
       this.ensureFeature(feature,value);
       return total + (this.weights[this.makeFeatureKey(feature,value)] || 0);
     },0);
     const effectiveStrength = this.getEffectiveStrength(position.positionID);
     const memorySuppression = this.memorySuppressionAlpha * Math.pow(effectiveStrength, this.memorySuppressionBeta);
     return {position,score:featureScore - memorySuppression,effectiveStrength};
   });

   const bestScore=Math.max(...scored.map(item=>item.score));
   const bestChoices=scored.filter(item=>item.score===bestScore);
   const index=Math.floor(Math.random()*bestChoices.length);
   return bestChoices[index].position.positionID;
 }
}
