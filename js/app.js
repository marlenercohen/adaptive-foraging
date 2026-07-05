
let experimentConfig=null;
let protocolDefinition=null;
let protocolEngine=null;
let stimulusLibrary=null;
let stimulusRegistry=new StimulusRegistry();
let availableStimuli=[];
let imgs=[];
const world=new World();
const logger=new Logger();
const experimentLogger=new ExperimentLogger();
let currentRule=null;
let currentRewardStructure=null;
let agent=null;
let agentFactory=new AgentFactory();
let rewardStructureFactory=new RewardStructureFactory();
let episodeTerminationPolicyFactory=new EpisodeTerminationPolicyFactory();
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
let currentPhaseInfo=null;
let previousPhaseInfo=null;
let currentAgentConfigKey=null;
let currentRewardStructureConfigKey=null;
let currentEpisodeTerminationPolicy=null;
let currentEpisodeTerminationPolicyConfigKey=null;
let loadedRuleDefinitions={};
let phaseRuleInstancesByFile={};
let stimulusLibrariesBySet={};
let stimulusSetDescriptorsByName={};
let currentEpisodeRewardCapacity=0;
let sessionEnded=false;

const appRuntime = window.APP_RUNTIME || {};
const isDebugMode = appRuntime.mode === 'debug';
const appFeatures = {
  experimenterPanel: isDebugMode && appRuntime.features?.experimenterPanel !== false,
  sessionDownload: isDebugMode && appRuntime.features?.sessionDownload !== false
};

async function loadExperimentConfig(){
  const response = await fetch('experiment.json');
  experimentConfig = await response.json();
  return experimentConfig;
}

async function loadProtocolDefinition(filePath){
  const response = await fetch(filePath);
  return response.json();
}

async function preloadProtocolAssets(engine){
  const phases = engine?.phases || [];
  const stimulusSets = [...new Set(phases.map(phase => phase.stimulusSet).filter(Boolean))];
  const ruleFiles = [...new Set(phases.map(phase => phase.ruleFile).filter(Boolean))];

  const stimulusEntries = await Promise.all(stimulusSets.map(async (setName) => {
    const descriptor = await stimulusRegistry.resolve(setName);
    const library = new StimulusLibrary(descriptor.metadataFile);
    await library.ready;
    return [setName, { descriptor, library }];
  }));
  stimulusSetDescriptorsByName = {};
  stimulusLibrariesBySet = {};
  stimulusEntries.forEach(([setName, payload]) => {
    stimulusSetDescriptorsByName[setName] = payload.descriptor;
    stimulusLibrariesBySet[setName] = payload.library;
  });

  const ruleEntries = await Promise.all(ruleFiles.map(async (filePath) => {
    const response = await fetch(filePath);
    const definitions = await response.json();
    const normalizedDefinitions = Array.isArray(definitions) ? definitions : [];
    const compiled = normalizedDefinitions
      .map(createRuleFromDefinition)
      .filter(Boolean);
    return {
      filePath,
      definitions: normalizedDefinitions,
      rule: new Rule(compiled)
    };
  }));

  loadedRuleDefinitions = {};
  phaseRuleInstancesByFile = {};
  ruleEntries.forEach(entry => {
    loadedRuleDefinitions[entry.filePath] = entry.definitions;
    phaseRuleInstancesByFile[entry.filePath] = entry.rule;
  });
}

function buildStimulusImagesForPhase(phase){
  stimulusLibrary = stimulusLibrariesBySet[phase.stimulusSet] || null;
  availableStimuli = stimulusLibrary ? stimulusLibrary.getAll() : [];

  const count = phase?.stimuliPerEpisode || 20;
  const samplingPopulation = buildStimulusPopulationForPhase(phase, availableStimuli);
  if(samplingPopulation.length < count){
    throw new Error(
      `Phase "${phase?.name || 'Unnamed phase'}" defines a stimulus population with ${samplingPopulation.length} entries, ` +
      `but stimuliPerEpisode requires ${count}.`
    );
  }
  imgs = sampleStimulusPopulation(samplingPopulation, count).map(stimulus => ({
    ...stimulus,
    label: stimulus?.label || stimulus?.display || ''
  }));

  const maxSelections = phase?.episodeTerminationPolicy?.maxParticipantSelections
    || phase?.episodeLength
    || imgs.length;
  if(!episodeController){
    episodeController = new EpisodeController(maxSelections);
  }
  episodeController.maxParticipantSelections = maxSelections;
}

function buildStimulusPopulationForPhase(phase, allStimuli){
  const populationIds = Array.isArray(phase?.stimulusPopulation)
    ? phase.stimulusPopulation
    : null;

  if(!populationIds){
    return [...allStimuli];
  }

  return populationIds.map((stimulusId, index) => {
    const stimulus = stimulusLibrary?.getById(stimulusId) || null;
    if(!stimulus){
      throw new Error(
        `Phase "${phase?.name || 'Unnamed phase'}" references unknown stimulus ID ${JSON.stringify(stimulusId)} ` +
        `at stimulusPopulation[${index}] in stimulus set "${phase?.stimulusSet || 'unknown'}".`
      );
    }
    return stimulus;
  });
}

function sampleStimulusPopulation(population, count){
  const pool = [...population];
  const sampled = [];
  while(sampled.length < count){
    const index = Math.floor(Math.random() * pool.length);
    sampled.push(pool.splice(index, 1)[0]);
  }
  return sampled;
}

function ensureAgentForPhase(phase){
  const agentConfig = phase?.agent || {};
  const workingMemoryConfig = phase?.workingMemory || {};
  const configKey = JSON.stringify({ agentConfig, workingMemoryConfig });
  if(!agent || configKey !== currentAgentConfigKey){
    agent = agentFactory.createAgent(agentConfig, {
      workingMemory: workingMemoryConfig
    });
    currentAgentConfigKey = configKey;
  }
}

function ensureRewardStructureForPhase(phase){
  const rewardStructureConfig = phase?.rewardStructure || { type: 'individual', rewardPerHit: 1 };
  const configKey = JSON.stringify(rewardStructureConfig);
  if(!currentRewardStructure || configKey !== currentRewardStructureConfigKey){
    currentRewardStructure = rewardStructureFactory.create(rewardStructureConfig);
    currentRewardStructureConfigKey = configKey;
  }
}

function ensureEpisodeTerminationPolicyForPhase(phase){
  const policyConfig = phase?.episodeTerminationPolicy || {
    type: 'standard',
    maxMoves: 20,
    endWhenRewardsExhausted: true
  };
  const configKey = JSON.stringify(policyConfig);
  if(!currentEpisodeTerminationPolicy || configKey !== currentEpisodeTerminationPolicyConfigKey){
    currentEpisodeTerminationPolicy = episodeTerminationPolicyFactory.create(policyConfig);
    currentEpisodeTerminationPolicyConfigKey = configKey;
  }

  if(episodeController){
    episodeController.maxParticipantSelections = currentEpisodeTerminationPolicy.maxMoves;
  }
}

function applyPhaseForEpisode(episodeNumber){
  if(!protocolEngine){
    currentRule = new Rule([]);
    currentPhaseInfo = null;
    return null;
  }
  const info = protocolEngine.getPhaseForEpisode(episodeNumber);
  const phase = info.phase;
  buildStimulusImagesForPhase(phase);
  ensureAgentForPhase(phase);
  ensureRewardStructureForPhase(phase);
  ensureEpisodeTerminationPolicyForPhase(phase);
  currentRule = phaseRuleInstancesByFile[phase.ruleFile] || new Rule([]);
  currentPhaseInfo = info;
  currentRuleIndex = info.phaseIndex;
  return info;
}

async function initializeGame(){
  experimentConfig = await loadExperimentConfig();
  protocolDefinition = await loadProtocolDefinition(experimentConfig.protocolFile || 'protocol.json');
  protocolEngine = new ProtocolEngine(protocolDefinition);
  await preloadProtocolAssets(protocolEngine);

  board.feedbackDurationMs = experimentConfig.feedbackDurationMs || board.feedbackDurationMs;
  agentDelayMs = experimentConfig.agentDelayMs || agentDelayMs;

  applyPhaseForEpisode(1);
  initializeExperimentLogging();
  if (appFeatures.experimenterPanel && window.ExperimenterPanel) {
    experimenterPanel = new ExperimenterPanel('experimenter-panel', {
      onDownloadSession: appFeatures.sessionDownload ? downloadSessionLog : null
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
  const allStimulusMetadata = Object.fromEntries(
    Object.entries(stimulusLibrariesBySet).map(([setName, library]) => [setName, library.getAll()])
  );
  const resolvedStimulusSets = Object.fromEntries(
    Object.entries(stimulusSetDescriptorsByName).map(([setName, descriptor]) => [setName, { ...descriptor }])
  );
  const metadata = {
    timestamp: new Date().toISOString(),
    softwareVersion: document.title || 'unknown',
    experimentConfiguration: experimentConfig,
    protocol: protocolEngine ? protocolEngine.getExecutedProtocol() : {},
    resolvedStimulusSets,
    stimulusMetadata: allStimulusMetadata,
    ruleDefinitions: loadedRuleDefinitions,
    rewardStructure: currentPhaseInfo?.phase?.rewardStructure || { rewardPerHit: 1 },
    agentConfiguration: currentPhaseInfo?.phase?.agent || {},
    workingMemoryConfiguration: currentPhaseInfo?.phase?.workingMemory || {},
    episodeTerminationPolicy: {
      ...(currentPhaseInfo?.phase?.episodeTerminationPolicy || {}),
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
  const currentPhase = currentPhaseInfo?.phase || {};
  return {
    currentBlock: currentBlockNumber,
    currentEpisode: episodeController?.episodeNumber ?? null,
    currentMove: episodeController?.participantSelections ?? null,
    currentPhase: {
      name: currentPhase.name || null,
      index: currentPhaseInfo?.phaseIndex ?? null,
      episodeWithinPhase: currentPhaseInfo?.phaseEpisode ?? null,
      stimulusSet: currentPhase.stimulusSet || null
    },
    currentRule: {
      index: currentRuleIndex,
      file: currentPhase.ruleFile || null,
      definition: currentPhase.ruleFile ? loadedRuleDefinitions[currentPhase.ruleFile] : null
    },
    currentRewardStructure: {
      ...(currentPhase.rewardStructure || {}),
      rewardsRemaining: episodeController?.rewardsRemaining ?? null,
      episodeRewardCapacity: currentEpisodeRewardCapacity
    },
    currentAgent: {
      type: currentPhase?.agent?.type ?? null,
      config: currentPhase?.agent ?? {},
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
      phaseIndex: currentRuleIndex,
      phaseName: currentPhaseInfo?.phase?.name || null,
      ruleFile: currentPhaseInfo?.phase?.ruleFile || null,
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
  const phase = currentPhaseInfo?.phase || null;
  const ruleLabel = phase ? `${phase.name} (${phase.ruleFile || '-'})` : '-';
  const agentType = phase?.agent?.type || '-';
  const rewardsRemaining = episodeController?.rewardsRemaining ?? '-';
  const episodesUntilNextSwitch = protocolEngine ? protocolEngine.episodesUntilNextPhase(episodeController?.episodeNumber || 1) : Infinity;
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

  const upcomingEpisodeNumber = (episodeController.episodeNumber || 0) + 1;
  const nextPhaseInfo = applyPhaseForEpisode(upcomingEpisodeNumber);
  const activeForUpcoming = currentRule || new Rule([]);
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
  currentRule = currentRule || activeForUpcoming;
  currentRuleIndex = nextPhaseInfo?.phaseIndex ?? null;
  const newBlockNumber = nextPhaseInfo?.blockNumber ?? 1;

  if(currentBlockNumber === null){
    experimentLogger.logEvent('block_start', {
      blockNumber: newBlockNumber,
      phaseIndex: currentRuleIndex,
      phaseName: currentPhaseInfo?.phase?.name || null,
      ruleFile: currentPhaseInfo?.phase?.ruleFile || null
    });
  } else if(newBlockNumber !== currentBlockNumber){
    experimentLogger.logEvent('block_end', {
      blockNumber: currentBlockNumber,
      phaseIndex: previousPhaseInfo?.phaseIndex ?? null,
      phaseName: previousPhaseInfo?.phase?.name || null,
      ruleFile: previousPhaseInfo?.phase?.ruleFile || null
    });
    experimentLogger.logEvent('block_start', {
      blockNumber: newBlockNumber,
      phaseIndex: currentRuleIndex,
      phaseName: currentPhaseInfo?.phase?.name || null,
      ruleFile: currentPhaseInfo?.phase?.ruleFile || null
    });
  }

  if(previousPhaseInfo && previousPhaseInfo.phase?.ruleFile !== currentPhaseInfo?.phase?.ruleFile){
    experimentLogger.logEvent('rule_change', {
      episodeNumber: episodeController.episodeNumber,
      fromPhaseIndex: previousPhaseInfo.phaseIndex,
      toPhaseIndex: currentPhaseInfo?.phaseIndex ?? null,
      fromRuleFile: previousPhaseInfo.phase?.ruleFile || null,
      toRuleFile: currentPhaseInfo?.phase?.ruleFile || null
    });
  }

  currentBlockNumber = newBlockNumber;
  previousPhaseInfo = currentPhaseInfo;

  experimentLogger.logEvent('episode_start', {
    blockNumber: currentBlockNumber,
    phaseIndex: currentPhaseInfo?.phaseIndex ?? null,
    phaseName: currentPhaseInfo?.phase?.name || null,
    episodeNumber: episodeController.episodeNumber,
    ruleIndex: currentRuleIndex,
    ruleFile: currentPhaseInfo?.phase?.ruleFile || null,
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
  if(episodeController && typeof episodeController.recordSelection === 'function'){
    episodeController.recordSelection();
  }
  const r=(currentRule || new Rule([])).evaluate(p);
  const reward=r.reward;
  const repeat=r.repeat;
  let rewardAllocation = null;
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
      rewardAllocation = (currentRewardStructure || rewardStructureFactory.create({ type: 'individual', rewardPerHit: 1 }))
        .distributeReward({
          actor,
          reward: true,
          gameState: {
            blockNumber: currentBlockNumber,
            episodeNumber: episodeController?.episodeNumber ?? null,
            moveNumber: episodeController?.participantSelections ?? null,
            scores: {
              humanScore,
              agentScore,
              humanTotalScore,
              agentTotalScore
            }
          }
        });

      const humanDelta = rewardAllocation?.allocation?.humanDelta || 0;
      const agentDelta = rewardAllocation?.allocation?.agentDelta || 0;
      humanScore += humanDelta;
      humanTotalScore += humanDelta;
      agentScore += agentDelta;
      agentTotalScore += agentDelta;
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
      rewardAllocation,
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
  const terminationDecision = (currentEpisodeTerminationPolicy || episodeTerminationPolicyFactory.create({
    type: 'standard',
    maxMoves: episodeController?.maxParticipantSelections ?? 20,
    endWhenRewardsExhausted: true
  })).evaluate({
    moveCount: episodeController?.totalSelections ?? episodeController?.participantSelections ?? 0,
    rewardsRemaining: episodeController?.rewardsRemaining ?? 0
  });

  if(terminationDecision.shouldEnd){
    experimentLogger.logEvent('episode_end', {
      blockNumber: currentBlockNumber,
      episodeNumber: episodeController.episodeNumber,
      moveCount: episodeController?.totalSelections ?? episodeController?.participantSelections ?? null,
      participantMoveCount: episodeController?.participantSelections ?? null,
      rewardsRemaining: episodeController?.rewardsRemaining ?? null,
      terminationReasons: terminationDecision.reasons,
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

