
class Rule{
 constructor(rules = []) {
   this.rules = rules;
 }

  evaluate(pos, context = {}){
   if(pos.resolved) return {reward:false,repeat:true};

   const metadata = pos.imageInstance?.features || {};
   const positionContext = {
     ...context,
     positionID: pos.positionID
   };
   const matched = this.rules.some(rule => rule.evaluate(metadata, positionContext));
   return {reward:matched,repeat:false};
 }

  isRewardExhaustionDefined(){
   return this.rules.every(rule => {
     if(typeof rule?.isRewardExhaustionDefined === 'function'){
       return rule.isRewardExhaustionDefined();
     }
     return rule?.rewardExhaustionDefined !== false;
   });
  }

  getInitialRewardCapacity(images = [], options = {}){
   if(!Array.isArray(images) || images.length === 0){
     return 0;
   }

   if(!this.isRewardExhaustionDefined()){
     return null;
   }

   return images.reduce((count, img) => {
     const result = this.evaluate({
       resolved: false,
       positionID: null,
       imageInstance: img
     }, options?.context || {});
     return count + (result.reward ? 1 : 0);
   }, 0);
  }
}

class FeatureRule {
 constructor(feature,operator,value){
   this.feature=feature;
   this.operator=operator;
   this.value=value;
   this.requiresDynamicContext = false;
   this.rewardExhaustionDefined = true;
 }

 evaluate(features){
   const actual = features?.[this.feature];
   if(actual===undefined || actual===null){
     return false;
   }

   switch(this.operator){
     case '==':
       return actual === this.value;
     case '>':
       return actual > this.value;
     case '<':
       return actual < this.value;
     default:
       return false;
   }
 }
}

class AndRule {
 constructor(rules = []) {
   this.rules = rules;
   this.requiresDynamicContext = this.rules.some(rule => Boolean(rule?.requiresDynamicContext));
   this.rewardExhaustionDefined = this.rules.every(rule => {
     if(typeof rule?.isRewardExhaustionDefined === 'function'){
       return rule.isRewardExhaustionDefined();
     }
     return rule?.rewardExhaustionDefined !== false;
   });
 }

 evaluate(features, context = {}){
   return this.rules.every(rule => rule.evaluate(features, context));
 }
}

class OrRule {
 constructor(rules = []) {
   this.rules = rules;
   this.requiresDynamicContext = this.rules.some(rule => Boolean(rule?.requiresDynamicContext));
   this.rewardExhaustionDefined = this.rules.every(rule => {
     if(typeof rule?.isRewardExhaustionDefined === 'function'){
       return rule.isRewardExhaustionDefined();
     }
     return rule?.rewardExhaustionDefined !== false;
   });
 }

 evaluate(features, context = {}){
   return this.rules.some(rule => rule.evaluate(features, context));
 }
}

class DistanceFromAgentRule {
 constructor(minimumDistance = 0){
   const numericDistance = Number(minimumDistance);
   this.minimumDistance = Number.isFinite(numericDistance)
     ? Math.max(0, Math.floor(numericDistance))
     : 0;
   this.requiresDynamicContext = true;
   this.rewardExhaustionDefined = false;
 }

 evaluate(_features, context = {}){
   const selectedPositionID = Number(context?.positionID);
   const previousReferencePositionID = Number(
     context?.previousReferencePositionID
     ?? (context?.actor === 'agent' ? context?.previousHumanPositionID : context?.previousAgentPositionID)
   );
   const boardColumnCount = Number(context?.boardColumnCount);

   if(!Number.isInteger(selectedPositionID) || !Number.isInteger(previousReferencePositionID)){
     return false;
   }
   if(!Number.isFinite(boardColumnCount) || boardColumnCount <= 0){
     return false;
   }

   const columns = Math.max(1, Math.floor(boardColumnCount));
   const humanRow = Math.floor(selectedPositionID / columns);
   const humanCol = selectedPositionID % columns;
  const agentRow = Math.floor(previousReferencePositionID / columns);
  const agentCol = previousReferencePositionID % columns;
   const manhattanDistance = Math.abs(humanRow - agentRow) + Math.abs(humanCol - agentCol);

   return manhattanDistance >= this.minimumDistance;
 }
}

function createRuleFromDefinition(definition){
  if(!definition || typeof definition !== 'object'){
    return null;
  }

  switch(definition.type){
    case 'feature':
      return new FeatureRule(definition.feature, definition.operator, definition.value);
    case 'distance-from-agent':
      return new DistanceFromAgentRule(definition.minimumDistance);
    case 'and':
      return new AndRule((definition.rules || []).map(createRuleFromDefinition).filter(Boolean));
    case 'or':
      return new OrRule((definition.rules || []).map(createRuleFromDefinition).filter(Boolean));
    default:
      return null;
  }
}

async function loadRules(rulePath = 'rules.json') {
  const response = await fetch(rulePath);
  const data = await response.json();
  return (Array.isArray(data) ? data : [])
    .map(createRuleFromDefinition)
    .filter(Boolean);
}

class RuleScheduler {
  constructor(ruleInstances = [], episodesPerRule = Infinity){
    this.ruleInstances = Array.isArray(ruleInstances) ? ruleInstances : [];
    this.episodesPerRule = episodesPerRule || Infinity;
  }

  getActiveRule(episodeNumber){
    if(!this.ruleInstances.length) return new Rule([]);
    const E = this.episodesPerRule;
    if(!isFinite(E) || E <= 0) return this.ruleInstances[0];
    const block = Math.floor(((episodeNumber || 1) - 1) / E);
    const idx = block % this.ruleInstances.length;
    return this.ruleInstances[Math.max(0, idx)];
  }

  episodesUntilNextSwitch(episodeNumber){
    if(!this.ruleInstances.length) return Infinity;
    const E = this.episodesPerRule;
    if(!isFinite(E) || E <= 0) return Infinity;
    const ep = episodeNumber || 1;
    const b = Math.floor((ep - 1) / E);
    const nextSwitchEpisode = (b + 1) * E + 1;
    const remaining = nextSwitchEpisode - ep;
    return Math.max(0, remaining);
  }
}
