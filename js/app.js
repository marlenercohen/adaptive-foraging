
const defs=['🦘','🐕','🐋','🐦','🐈','🪑','🚗','📘','🎸','🏠'];
const imgs=Array.from({length:20},(_,i)=>({id:i,label:defs[i%defs.length]}));
const world=new World();
const logger=new Logger();
const rule=new Rule();
const agent=new RandomAgent();
const episodeController=new EpisodeController(imgs.length);
const board=new Board("board",id=>makeSelection(id,'human'));
let currentTurn='human';
const agentDelayMs=700;
let humanScore=0;
let agentScore=0;

function countRewards(images){
  return images.reduce((count,img)=>count + (rule.evaluate({resolved:false,imageInstance:img}).reward ? 1 : 0),0);
}

function startEpisode(){
  episodeController.resetEpisode(countRewards(imgs));
  world.startEpisode(imgs);
  humanScore=0;
  agentScore=0;
  board.draw(world);
  updateScores();
  setTurn('human');
}

function updateScores(){
  document.getElementById("human-score").textContent="Human score: "+humanScore;
  document.getElementById("agent-score").textContent="Agent score: "+agentScore;
}

function setTurn(turn){
  currentTurn=turn;
  document.getElementById("turn-indicator").textContent=turn==='human'?'Your move':'Agent move';
}

function makeSelection(id,actor){
  if(currentTurn!==actor)return;
  const p=world.getPosition(id);
  const r=rule.evaluate(p);
  const reward=r.reward;
  const repeat=r.repeat;
  if(!repeat){
    p.resolved=true;
    if(actor==='human'){
      episodeController.recordParticipantSelection();
    }
    if(reward){
      world.addReward(1);
      if(actor==='human'){
        humanScore+=1;
      } else {
        agentScore+=1;
      }
      episodeController.recordRewardCollected();
    }
  }
  board.feedback(id,reward);
  updateScores();
  logger.log("selection",{actor,positionID:id,imageID:p.imageInstance.id,reward:Boolean(reward),repeat,humanScore,agentScore,episodeNumber:episodeController.episodeNumber,participantSelectionsRemaining:Math.max(0,episodeController.maxParticipantSelections-episodeController.participantSelections)});
  if(episodeController.isEpisodeComplete()){
    startEpisode();
    return;
  }
  if(actor==='human'){
    setTurn('agent');
    setTimeout(agentMove,agentDelayMs);
  } else {
    setTurn('human');
  }
}

startEpisode();

function agentMove(){
  if(currentTurn!=='agent')return;
  const choice=agent.choose(world);
  if(choice!==undefined){
    makeSelection(choice,'agent');
  }
}

