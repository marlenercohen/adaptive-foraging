function summary = summarizeSession(sessionInput)
%SUMMARIZESESSION Compute whole-session descriptive metrics.
%   SUMMARY = SUMMARIZESESSION(SESSIONINPUT) returns descriptive statistics
%   for one session. SESSIONINPUT can be a normalized session struct from
%   LOADSESSION or a JSON file path.

    session = afResolveSessionInput(sessionInput);

    metadata = afField(session, 'sessionMetadata', struct());
    protocol = afField(metadata, 'protocol', struct());
    phases = afProtocolPhases(protocol);

    episodeStartEvents = afEventsByType(session, 'episode_start');
    episodeEndEvents = afEventsByType(session, 'episode_end');
    ruleChangeEvents = afEventsByType(session, 'rule_change');
    humanMoveEvents = afEventsByType(session, 'human_move');
    agentMoveEvents = afEventsByType(session, 'agent_move');
    rewardEvents = afEventsByType(session, 'reward_delivered');
    sessionEndEvents = afEventsByType(session, 'session_end');

    [participantRewards, agentRewards] = afRewardTotals(rewardEvents);

    participantScore = participantRewards;
    agentScore = agentRewards;
    if ~isempty(sessionEndEvents)
        finalData = afField(sessionEndEvents(end), 'data', struct());
        finalScores = afField(finalData, 'finalScores', struct());
        participantScore = afField(finalScores, 'humanScore', participantScore);
        agentScore = afField(finalScores, 'agentScore', agentScore);
    end

    summary = struct();
    summary.sourceFile = afField(session, 'sourceFile', "");
    summary.schemaVersion = afField(session, 'schemaVersion', "");
    summary.experimentMetadata = metadata;
    summary.protocolMetadata = protocol;
    summary.stimulusSet = afUniquePhaseField(phases, 'stimulusSet');
    summary.rulesEncountered = afRulesEncountered(session, phases);
    summary.rewardStructuresEncountered = afUniquePhaseField(phases, 'rewardStructure');
    summary.workingMemoryParameters = afUniquePhaseField(phases, 'workingMemory');
    summary.terminationPolicy = afUniquePhaseField(phases, 'episodeTerminationPolicy');
    summary.numberOfEpisodes = max(numel(episodeStartEvents), numel(episodeEndEvents));
    summary.numberOfRuleSwitches = numel(ruleChangeEvents);
    summary.participantScore = participantScore;
    summary.agentScore = agentScore;
    summary.totalTurns = numel(humanMoveEvents) + numel(agentMoveEvents);
    summary.participantRewards = participantRewards;
    summary.agentRewards = agentRewards;
end
