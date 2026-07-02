
let experimentConfig=null;
let stimulusLibrary=null;
let availableStimuli=[];
let imgs=[];
const world=new World();
const logger=new Logger();
let rule=new Rule();
let agent=null;
let agentFactory=new AgentFactory();
let episodeController=null;
const board=new Board("board",id=>makeSelection(id,'human'));
let currentTurn='human';
let agentDelayMs=700;
const episodePauseMs=1000;
let humanScore=0;
let agentScore=0;
let agentMoveTimer=null;
let episodeTransitionTimer=null;

async function loadExperimentConfig(){
  const response = await fetch('experiment.json');
  experimentConfig = await response.json();
  return experimentConfig;
}

function buildStimulusImages(){
  availableStimuli=stimulusLibrary.getAll();
  const count = experimentConfig?.stimuliPerEpisode || 20;
  imgs=Array.from({length:count},(_,i)=>({
    id:i,
    label:stimulusLibrary.getById(i%availableStimuli.length)?.display || '',
    features:stimulusLibrary.getById(i%availableStimuli.length)?.features || {}
  }));
  episodeController=new EpisodeController(experimentConfig?.episodeLength || imgs.length);
}

async function initializeGame(){
  experimentConfig = await loadExperimentConfig();
  stimulusLibrary = new StimulusLibrary(experimentConfig.stimulusMetadataFile);
  await stimulusLibrary.ready;
  const loadedRules = await loadRules(experimentConfig.ruleFile);
  rule = new Rule(loadedRules);
  board.feedbackDurationMs = experimentConfig.feedbackDurationMs || board.feedbackDurationMs;
  agentDelayMs = experimentConfig.agentDelayMs || agentDelayMs;
  agent = agentFactory.createAgent(experimentConfig.agent);
  buildStimulusImages();
  startEpisode();
}

function countRewards(images){
  return images.reduce((count,img)=>count + (rule.evaluate({resolved:false,imageInstance:img}).reward ? 1 : 0),0);
}

function startEpisode(){
  if(episodeController===null){
    return;
  }
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
  if(actor==='agent' && agent && typeof agent.receiveFeedback === 'function'){
    agent.receiveFeedback(p.imageInstance, p.imageInstance?.features || {}, Boolean(reward));
  }
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

initializeGame();

function agentMove(){
  agentMoveTimer=null;
  if(currentTurn!=='agent')return;
  const choice=agent.choose(world);
  if(choice!==undefined){
    makeSelection(choice,'agent');
  }
}

