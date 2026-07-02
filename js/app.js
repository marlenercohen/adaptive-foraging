
const stimulusLibrary=new StimulusLibrary([
  {id:0,label:'🦘'},
  {id:1,label:'🐕'},
  {id:2,label:'🐋'},
  {id:3,label:'🐦'},
  {id:4,label:'🐈'},
  {id:5,label:'🪑'},
  {id:6,label:'🚗'},
  {id:7,label:'📘'},
  {id:8,label:'🎸'},
  {id:9,label:'🏠'}
]);
const availableStimuli=stimulusLibrary.getAll();
const imgs=Array.from({length:20},(_,i)=>({id:i,label:stimulusLibrary.getById(i%availableStimuli.length).label}));
const world=new World();
const logger=new Logger();
const rule=new Rule();
const agent=new RandomAgent();
const episodeController=new EpisodeController(imgs.length);
const board=new Board("board",id=>makeSelection(id,'human'));
let currentTurn='human';
const agentDelayMs=700;
const episodePauseMs=1000;
let humanScore=0;
let agentScore=0;
let agentMoveTimer=null;
let episodeTransitionTimer=null;

function countRewards(images){
  return images.reduce((count,img)=>count + (rule.evaluate({resolved:false,imageInstance:img}).reward ? 1 : 0),0);
}

function startEpisode(){
  if(episodeTransitionTimer!==null){
    clearTimeout(episodeTransitionTimer);
    episodeTransitionTimer=null;
  }
  if(agentMoveTimer!==null){
    clearTimeout(agentMoveTimer);
    agentMoveTimer=null;
  }
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
    if(agentMoveTimer!==null){
      clearTimeout(agentMoveTimer);
      agentMoveTimer=null;
    }
    setTurn('human');
    episodeTransitionTimer=setTimeout(()=>startEpisode(),episodePauseMs);
    return;
  }
  if(actor==='human'){
    setTurn('agent');
    agentMoveTimer=setTimeout(agentMove,agentDelayMs);
  } else {
    setTurn('human');
  }
}

startEpisode();

function agentMove(){
  agentMoveTimer=null;
  if(currentTurn!=='agent')return;
  const choice=agent.choose(world);
  if(choice!==undefined){
    makeSelection(choice,'agent');
  }
}

