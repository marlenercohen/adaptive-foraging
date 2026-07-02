
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
