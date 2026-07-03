
let experimentConfig=null;
let stimulusLibrary=null;
let availableStimuli=[];
let imgs=[];
const world=new World();
const logger=new Logger();
const experimentLogger=new ExperimentLogger();
let ruleScheduler=null;
let currentRule=null;
let agent=null;
let agentFactory=new AgentFactory();
let episodeController=null;
const board=new Board("board",id=>makeSelection(id,'human'));
let experimenterPanel=null;
let currentTurn='human';
let lastAgentSelectionId=null;
let agentDelayMs=700;
const episodePauseMs=1000;
let humanScore=0;
let agentScore=0;
let humanTotalScore=0;
let agentTotalScore=0;
let agentMoveTimer=null;
let episodeTransitionTimer=null;
let currentRuleIndex=null;
let currentBlockNumber=null;
let previousRuleIndex=null;
let loadedRuleDefinitions={};
let currentRuleFiles=[];
let currentEpisodeRewardCapacity=0;
let sessionEnded=false;

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
  currentRuleFiles = ruleFiles;

  const rawRuleFiles = await Promise.all(ruleFiles.map(async (filePath) => {
    const response = await fetch(filePath);
    return { filePath, definitions: await response.json() };
  }));
  loadedRuleDefinitions = rawRuleFiles.reduce((acc, item) => {
    acc[item.filePath] = item.definitions;
    return acc;
  }, {});

  const loadedPerFile = await Promise.all(ruleFiles.map(f => loadRules(f)));
  const ruleInstances = loadedPerFile.map(arr => new Rule(arr));
  ruleScheduler = new RuleScheduler(ruleInstances, experimentConfig.episodesPerRule || Infinity);

  board.feedbackDurationMs = experimentConfig.feedbackDurationMs || board.feedbackDurationMs;
  agentDelayMs = experimentConfig.agentDelayMs || agentDelayMs;
  agent = agentFactory.createAgent(experimentConfig.agent, {
    workingMemory: experimentConfig.workingMemory || {}
  });
  buildStimulusImages();
  initializeExperimentLogging();
  if (experimentConfig.debug && window.ExperimenterPanel) {
    experimenterPanel = new ExperimenterPanel('experimenter-panel', {
      onDownloadSession: downloadSessionLog
    });
  }
  startEpisode();
  updateExperimenterPanel();
}

function formatTimestampForFileName(date = new Date()){
  const year = String(date.getFullYear());
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${year}-${month}-${day}_${hours}${minutes}`;
}

function downloadSessionLog(){
  const sessionData = experimentLogger.getSessionData();
  const json = JSON.stringify(sessionData, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const fileName = `adaptive_foraging_${formatTimestampForFileName()}.json`;

  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

function getRuleIndexForEpisode(episodeNumber){
  if(!ruleScheduler || !ruleScheduler.ruleInstances || !ruleScheduler.ruleInstances.length) return null;
  const active = ruleScheduler.getActiveRule(episodeNumber);
  const idx = ruleScheduler.ruleInstances.indexOf(active);
  return idx >= 0 ? idx : null;
}

function getBlockNumberForEpisode(episodeNumber){
  const E = experimentConfig?.episodesPerRule;
  if(!isFinite(E) || E <= 0) return 1;
  return Math.floor(((episodeNumber || 1) - 1) / E) + 1;
}

function getAgentInternalState(){
  if(!agent) return {};
  const state = {};
  Object.keys(agent).forEach(key => {
    const value = agent[key];
    if(typeof value !== 'function'){
      state[key] = value;
    }
  });
  return state;
}

function initializeExperimentLogging(){
  const metadata = {
    timestamp: new Date().toISOString(),
    softwareVersion: document.title || 'unknown',
    experimentConfiguration: experimentConfig,
    protocol: experimentConfig?.protocol ?? {},
    stimulusMetadata: availableStimuli,
    ruleDefinitions: loadedRuleDefinitions,
    rewardStructure: {
      episodesPerRule: experimentConfig?.episodesPerRule ?? null,
      stimuliPerEpisode: experimentConfig?.stimuliPerEpisode ?? null,
      rewardUnitValue: 1
    },
    agentConfiguration: experimentConfig?.agent ?? {},
    workingMemoryConfiguration: experimentConfig?.workingMemory ?? {},
    episodeTerminationPolicy: {
      maxParticipantSelections: episodeController?.maxParticipantSelections ?? null,
      endsOnRewardsExhausted: true,
      endsOnSelectionLimit: true
    },
    randomSeeds: experimentConfig?.randomSeeds ?? {
      source: 'Math.random',
      deterministicSeed: null
    }
  };
  experimentLogger.beginSession(metadata);
}

function buildReplayState(){
  return {
    currentBlock: currentBlockNumber,
    currentEpisode: episodeController?.episodeNumber ?? null,
    currentMove: episodeController?.participantSelections ?? null,
    currentRule: {
      index: currentRuleIndex,
      file: currentRuleIndex !== null ? (currentRuleFiles[currentRuleIndex] || null) : null,
      definition: currentRuleIndex !== null ? loadedRuleDefinitions[currentRuleFiles[currentRuleIndex]] : null
    },
    currentRewardStructure: {
      rewardsRemaining: episodeController?.rewardsRemaining ?? null,
      episodeRewardCapacity: currentEpisodeRewardCapacity
    },
    currentAgent: {
      type: experimentConfig?.agent?.type ?? null,
      config: experimentConfig?.agent ?? {},
      internalState: getAgentInternalState()
    },
    currentScores: {
      humanScore,
      agentScore
    },
    remainingRewards: episodeController?.rewardsRemaining ?? null,
    stimulusLocations: (world?.positions || []).map(pos => ({
      positionID: pos.positionID,
      resolved: pos.resolved,
      imageInstance: pos.imageInstance
    })),
    visitedLocations: (world?.positions || [])
      .filter(pos => pos.resolved)
      .map(pos => pos.positionID),
    turn: currentTurn,
    lastAgentSelectionId
  };
}

function logStateSnapshot(reason, extra = {}){
  experimentLogger.recordSnapshot(buildReplayState(), { reason, ...extra });
}

function finalizeExperimentLogging(reason){
  if(sessionEnded) return;
  sessionEnded = true;
  if(currentBlockNumber !== null){
    experimentLogger.logEvent('block_end', {
      blockNumber: currentBlockNumber,
      ruleIndex: currentRuleIndex,
      reason
    });
  }
  experimentLogger.endSession({
    reason,
    completedEpisodes: episodeController?.episodeNumber ?? 0,
    finalScores: {
      humanScore,
      agentScore
    }
  });
  window.__lastExperimentLog = experimentLogger.getSessionData();
}

function getExperimenterState(){
  const episodeNum = episodeController ? episodeController.episodeNumber : 0;
  const moveNum = episodeController ? episodeController.participantSelections : 0;
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
  return {episodeName: experimentConfig?.name ?? '-', episodeNumber:episodeNum, moveNumber:moveNum, ruleLabel, agentType, rewardsRemaining, episodesUntilNextSwitch};
}

function getAgentScoreForFeatures(features){
  if(!agent) return 0;
  if(typeof agent.scoreFeatures === 'function'){
    return agent.scoreFeatures(features);
  }

  const weights = agent.weights || {};
  return Object.entries(features || {}).reduce((sum,[feature,value])=>{
    const key = `${feature}=${value}`;
    return sum + (weights[key] || 0);
  },0);
}

function buildPredictionRows(){
  if(!world || !experimenterPanel) return [];
  const activeRule = currentRule || new Rule([]);
  const unresolved = world.positions.filter(p=>!p.resolved);
  const rows = [...unresolved];

  if(lastAgentSelectionId !== null){
    const lastSelection = world.getPosition(lastAgentSelectionId);
    if(lastSelection && lastSelection.resolved && !unresolved.some(p => p.positionID === lastSelection.positionID)){
      rows.push(lastSelection);
    }
  }

  return rows.map(position=>{
    const features = position.imageInstance?.features || {};
    const score = getAgentScoreForFeatures(features);
    const reward = activeRule.evaluate(position).reward;
    return {
      id: position.positionID,
      icon: position.imageInstance?.label || '',
      score,
      rewarded: reward,
      chosen: position.positionID === lastAgentSelectionId
    };
  });
}

function updateExperimenterPanel(){
  if(!experimenterPanel) return;
  experimenterPanel.updateExperiment(getExperimenterState());
  experimenterPanel.updatePredictions(buildPredictionRows());
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
  currentEpisodeRewardCapacity = countRewards(imgs, activeForUpcoming);
  episodeController.resetEpisode(currentEpisodeRewardCapacity);
  world.startEpisode(imgs);
  if(agent && typeof agent.onEpisodeStart === 'function'){
    agent.onEpisodeStart();
  }
  humanScore=0;
  agentScore=0;
  lastAgentSelectionId=null;
  board.draw(world);
  updateScores();
  // Set the current rule for this episode (episodeNumber was incremented by resetEpisode)
  currentRule = ruleScheduler ? ruleScheduler.getActiveRule(episodeController.episodeNumber) : activeForUpcoming;
  currentRuleIndex = getRuleIndexForEpisode(episodeController.episodeNumber);
  const newBlockNumber = getBlockNumberForEpisode(episodeController.episodeNumber);

  if(currentBlockNumber === null){
    experimentLogger.logEvent('block_start', {
      blockNumber: newBlockNumber,
      ruleIndex: currentRuleIndex,
      ruleFile: currentRuleIndex !== null ? currentRuleFiles[currentRuleIndex] : null
    });
  } else if(newBlockNumber !== currentBlockNumber){
    experimentLogger.logEvent('block_end', {
      blockNumber: currentBlockNumber,
      ruleIndex: previousRuleIndex
    });
    experimentLogger.logEvent('block_start', {
      blockNumber: newBlockNumber,
      ruleIndex: currentRuleIndex,
      ruleFile: currentRuleIndex !== null ? currentRuleFiles[currentRuleIndex] : null
    });
  }

  if(previousRuleIndex !== null && currentRuleIndex !== previousRuleIndex){
    experimentLogger.logEvent('rule_change', {
      episodeNumber: episodeController.episodeNumber,
      fromRuleIndex: previousRuleIndex,
      toRuleIndex: currentRuleIndex,
      fromRuleFile: currentRuleFiles[previousRuleIndex] || null,
      toRuleFile: currentRuleFiles[currentRuleIndex] || null
    });
  }

  currentBlockNumber = newBlockNumber;
  previousRuleIndex = currentRuleIndex;

  experimentLogger.logEvent('episode_start', {
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController.episodeNumber,
    ruleIndex: currentRuleIndex,
    ruleFile: currentRuleIndex !== null ? currentRuleFiles[currentRuleIndex] : null,
    rewardsAvailable: episodeController?.rewardsRemaining ?? null,
    maxSelections: episodeController?.maxParticipantSelections ?? null
  });
  logStateSnapshot('episode_start', {
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController.episodeNumber
  });
  setTurn('human');
  updateExperimenterPanel();
}

function updateScores(){
  document.getElementById("human-score").textContent="Human score: "+humanScore;
  document.getElementById("agent-score").textContent="Agent score: "+agentScore;
  document.getElementById("human-total-score").textContent="Human Total Score: "+humanTotalScore;
  document.getElementById("agent-total-score").textContent="Agent Total Score: "+agentTotalScore;
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
  if(agent && typeof agent.observeStimulusSelection === 'function'){
    agent.observeStimulusSelection(id);
  }

  experimentLogger.logEvent('stimulus_selection', {
    actor,
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController?.episodeNumber ?? null,
    moveNumber: episodeController?.participantSelections ?? null,
    positionID: id,
    stimulusID: p.imageInstance?.id ?? null,
    repeated: Boolean(repeat)
  });
  if(repeat){
    experimentLogger.logEvent('repeated_stimulus_selection', {
      actor,
      blockNumber: currentBlockNumber,
      episodeNumber: episodeController?.episodeNumber ?? null,
      moveNumber: episodeController?.participantSelections ?? null,
      positionID: id,
      stimulusID: p.imageInstance?.id ?? null
    });
  }

  if(!repeat){
    p.resolved=true;
    if(actor==='human'){
      episodeController.recordParticipantSelection();
    }
    if(reward){
      world.addReward(1);
      if(actor==='human'){
        humanScore+=1;
        humanTotalScore+=1;
      } else {
        agentScore+=1;
        agentTotalScore+=1;
      }
      episodeController.recordRewardCollected();
    }
  }
  board.feedback(id,reward);
  updateScores();

  experimentLogger.logEvent(actor === 'human' ? 'human_move' : 'agent_move', {
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController?.episodeNumber ?? null,
    moveNumber: episodeController?.participantSelections ?? null,
    positionID: id,
    stimulusID: p.imageInstance?.id ?? null,
    reward: Boolean(reward),
    repeat: Boolean(repeat)
  });

  if(reward && !repeat){
    experimentLogger.logEvent('reward_delivered', {
      actor,
      blockNumber: currentBlockNumber,
      episodeNumber: episodeController?.episodeNumber ?? null,
      moveNumber: episodeController?.participantSelections ?? null,
      positionID: id,
      stimulusID: p.imageInstance?.id ?? null,
      rewardValue: 1,
      rewardsRemaining: episodeController?.rewardsRemaining ?? null
    });
  }

  experimentLogger.logEvent('score_update', {
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController?.episodeNumber ?? null,
    moveNumber: episodeController?.participantSelections ?? null,
    humanScore,
    agentScore,
    humanTotalScore,
    agentTotalScore,
    rewardsRemaining: episodeController?.rewardsRemaining ?? null
  });

  if(actor==='agent' && agent && typeof agent.receiveFeedback === 'function'){
    agent.receiveFeedback(p.imageInstance, p.imageInstance?.features || {}, Boolean(reward));
  }
  logger.log("selection",{actor,positionID:id,imageID:p.imageInstance.id,reward:Boolean(reward),repeat,humanScore,agentScore,episodeNumber:episodeController.episodeNumber,participantSelectionsRemaining:Math.max(0,episodeController.maxParticipantSelections)});
  if(actor === 'agent'){
    lastAgentSelectionId = id;
  }
  if(experimenterPanel){
    experimenterPanel.updateAgent({
      lastStimulus: p.imageInstance?.id,
      lastRewarded: Boolean(reward),
      weights: agent?.weights || {}
    });
    experimenterPanel.pushMove({
      episode: episodeController.episodeNumber,
      move: episodeController.participantSelections,
      stimulus: p.imageInstance?.id,
      rewarded: Boolean(reward)
    });
  }
  logStateSnapshot('post_move', {
    actor,
    blockNumber: currentBlockNumber,
    episodeNumber: episodeController?.episodeNumber ?? null,
    moveNumber: episodeController?.participantSelections ?? null,
    positionID: id,
    stimulusID: p.imageInstance?.id ?? null,
    reward: Boolean(reward),
    repeat: Boolean(repeat)
  });
  updateExperimenterPanel();
  if(episodeController.isEpisodeComplete()){
    experimentLogger.logEvent('episode_end', {
      blockNumber: currentBlockNumber,
      episodeNumber: episodeController.episodeNumber,
      moveCount: episodeController?.participantSelections ?? null,
      rewardsRemaining: episodeController?.rewardsRemaining ?? null,
      finalScores: { humanScore, agentScore }
    });
    logStateSnapshot('episode_end', {
      blockNumber: currentBlockNumber,
      episodeNumber: episodeController.episodeNumber
    });
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

window.addEventListener('beforeunload', () => {
  finalizeExperimentLogging('beforeunload');
});

function agentMove(){
  agentMoveTimer=null;
  if(currentTurn!=='agent')return;
  const choice=agent.choose(world);
  if(choice!==undefined){
    makeSelection(choice,'agent');
  }
}

