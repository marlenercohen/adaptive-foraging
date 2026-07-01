/*
 * board.js
 */

export class Board{

    constructor(containerID,onClick){
        this.container=document.getElementById(containerID);
        this.onClick=onClick;
    }

    draw(world){
        this.container.innerHTML="";

        world.positions.forEach(position=>{
            const tile=document.createElement("button");
            tile.className="tile";
            tile.textContent=position.imageInstance.label;
            tile.onclick=()=>this.onClick(position.positionID);
            this.container.appendChild(tile);
        });
    }

}
