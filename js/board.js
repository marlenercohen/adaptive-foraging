
class Board{
 constructor(id,cb,feedbackDurationMs=500){this.el=document.getElementById(id);this.cb=cb;this.feedbackDurationMs=feedbackDurationMs;}
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
   setTimeout(()=>o.remove(),this.feedbackDurationMs);
   t.classList.add("selected");
   setTimeout(()=>t.classList.remove("selected"),this.feedbackDurationMs+150);
 }
}
