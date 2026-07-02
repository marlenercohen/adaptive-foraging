
class Rule{
 constructor(rules = []) {
   this.rules = rules;
 }

  evaluate(pos){
   if(pos.resolved) return {reward:false,repeat:true};

   const metadata = pos.imageInstance?.features || {};
   const matched = this.rules.some(rule => rule.evaluate(metadata));
   return {reward:matched,repeat:false};
 }
}

class FeatureRule {
 constructor(feature,operator,value){
   this.feature=feature;
   this.operator=operator;
   this.value=value;
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
 }

 evaluate(features){
   return this.rules.every(rule => rule.evaluate(features));
 }
}

class OrRule {
 constructor(rules = []) {
   this.rules = rules;
 }

 evaluate(features){
   return this.rules.some(rule => rule.evaluate(features));
 }
}

function createRuleFromDefinition(definition){
  if(!definition || typeof definition !== 'object'){
    return null;
  }

  switch(definition.type){
    case 'feature':
      return new FeatureRule(definition.feature, definition.operator, definition.value);
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
