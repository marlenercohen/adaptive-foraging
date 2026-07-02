class StatusPanel{
 constructor(containerId){
   this.el=document.getElementById(containerId);
 }

 update(world, episodeController){
   if(!this.el)return;
   const selectionsRemaining=Math.max(0, episodeController.maxParticipantSelections-episodeController.participantSelections);
   this.el.innerHTML=`
     <div class="status-panel">
       <div><strong>Episode number:</strong> ${episodeController.episodeNumber}</div>
       <div><strong>Episode score:</strong> ${world.episodeScore}</div>
       <div><strong>Session score:</strong> ${world.sessionScore}</div>
       <div><strong>Selections remaining:</strong> ${selectionsRemaining}</div>
       <div><strong>Rewards remaining:</strong> ${episodeController.rewardsRemaining}</div>
     </div>
   `;
 }
}
