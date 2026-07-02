
class Rule{
 evaluate(pos){
   if(pos.resolved) return {reward:false,repeat:true};
   const animal=["🦘","🐕","🐋","🐦","🐈"].includes(pos.imageInstance.label);
   return {reward:animal,repeat:false};
 }
}
