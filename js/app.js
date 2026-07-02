
let experimentConfig=null;
let stimulusLibrary=null;
let availableStimuli=[];
let imgs=[];
const world=new World();
const logger=new Logger();
let ruleScheduler=null;
let currentRule=null;
let agent=null;
let agentFactory=new AgentFactory();
let episodeController=null;
const board=new Board("board",id=>makeSelection(id,'human'));
let experimenterPanel=null;
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

  // support either ruleFiles (array) or legacy ruleFile
  const ruleFiles = experimentConfig.ruleFiles && Array.isArray(experimentConfig.ruleFiles)
    ? experimentConfig.ruleFiles
    : (experimentConfig.ruleFile ? [experimentConfig.ruleFile] : ['rules.json']);

  const loadedPerFile = await Promise.all(ruleFiles.map(f => loadRules(f)));
  const ruleInstances = loadedPerFile.map(arr => new Rule(arr));
  ruleScheduler = new RuleScheduler(ruleInstances, experimentConfig.episodesPerRule || Infinity);

  board.feedbackDurationMs = experimentConfig.feedbackDurationMs || board.feedbackDurationMs;
  agentDelayMs = experimentConfig.agentDelayMs || agentDelayMs;
  agent = agentFactory.createAgent(experimentConfig.agent);
  buildStimulusImages();
  // create experimenter panel and show initial state
  if(window.ExperimenterPanel){
    experimenterPanel = new ExperimenterPanel('experimenter-panel');
  }
  startEpisode();
  updateExperimenterPanel();
}

function getExperimenterState(){
  const episodeNum = episodeController ? episodeController.episodeNumber : 0;
  let ruleIndex = null;
  if(ruleScheduler && ruleScheduler.ruleInstances && currentRule){
    ruleIndex = ruleScheduler.ruleInstances.indexOf(currentRule);
    if(ruleIndex<0) ruleIndex = null;
  }
  const ruleLabel = (ruleIndex!==null && experimentConfig && experimentConfig.ruleFiles)
    ? `${experimentConfig.ruleFiles[ruleIndex] || ('rule#'+ruleIndex)}`
    : (ruleIndex!==null ? `rule#${ruleIndex}` : '-');
  const agentType = experimentConfig?.agent?.type || '-';
  const rewardsRemaining = episodeController?.rewardsRemaining ?? '-';
  const episodesUntilNextSwitch = ruleScheduler ? ruleScheduler.episodesUntilNextSwitch(episodeController?.episodeNumber || 0) : Infinity;
  return {episodeNumber:episodeNum, ruleIndex:ruleLabel, agentType, rewardsRemaining, episodesUntilNextSwitch};
}

function updateExperimenterPanel(){
  if(!experimenterPanel) return;
  experimenterPanel.update(getExperimenterState());
}

function countRewards(images, activeRule){
  const r = activeRule || currentRule || new Rule([]);
  return images.reduce((count,img)=>count + (r.evaluate({resolved:false,imageInstance:img}).reward ? 1 : 0),0);
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
  // Determine which rule will be active for the upcoming episode
  const upcomingEpisodeNumber = (episodeController.episodeNumber || 0) + 1;
  const activeForUpcoming = ruleScheduler ? ruleScheduler.getActiveRule(upcomingEpisodeNumber) : new Rule([]);
  episodeController.resetEpisode(countRewards(imgs, activeForUpcoming));
  world.startEpisode(imgs);
  humanScore=0;
  agentScore=0;
  board.draw(world);
  updateScores();
  // Set the current rule for this episode (episodeNumber was incremented by resetEpisode)
  currentRule = ruleScheduler ? ruleScheduler.getActiveRule(episodeController.episodeNumber) : activeForUpcoming;
  setTurn('human');
  updateExperimenterPanel();
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
  const r=(currentRule || new Rule([])).evaluate(p);
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
  updateExperimenterPanel();
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

