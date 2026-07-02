
class Board{
 constructor(id,cb){this.el=document.getElementById(id);this.cb=cb;}
 draw(world){
  this.el.innerHTML="";
  world.positions.forEach(p=>{
    const b=document.createElement("button");
    b.className="tile";
    b.dataset.pos=p.positionID;
    b.textContent=p.imageInstance.label;
    b.onclick=()=>this.cb(p.positionID);
    this.el.appendChild(b);
  });
 }
 feedback(id,hit){
   const t=this.el.querySelector(`[data-pos="${id}"]`);
   const o=document.createElement("div");
   o.className="overlay "+(hit?"hit":"miss");
   o.textContent=hit?"◯":"✕";
   t.appendChild(o);
   setTimeout(()=>o.remove(),500);
   t.classList.add("selected");
   setTimeout(()=>t.classList.remove("selected"),650);
 }
}
