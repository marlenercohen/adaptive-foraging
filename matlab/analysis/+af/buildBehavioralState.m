function behavioralState = buildBehavioralState(episodeState)
%af.buildBehavioralState Descriptive behavioral state before each human decision.
%   BEHAVIORALSTATE = af.buildBehavioralState(EPISODESTATE) returns one row
%   per human decision with descriptive variables summarizing the observed
%   history available immediately before that decision.
%
%   The function uses only reconstructed episode state. It does not rebuild
%   the board, re-evaluate rules, fit models, or perform statistical tests.

    if nargin < 1
        error('af:buildBehavioralState:MissingInput', ...
            'episodeState is required.');
    end
    if ~istable(episodeState)
        error('af:buildBehavioralState:InvalidInputType', ...
            'episodeState must be a table returned by af.reconstructEpisodeState().');
    end

    requiredVars = {
        'eventSeq', 'episode', 'actor', 'block', 'phase', 'trialWithinEpisode', ...
        'chosenReward', 'chosenRepeat', 'chosenSatisfiesRule', 'chosenStimulusID', ...
        'chosenPositionID', 'availablePositionIDs', 'availableStimulusIDs', ...
        'availableMatchingPositionIDs', 'availableMatchingStimulusIDs'
    };
    assertTableVariables(episodeState, requiredVars, ...
        'af:buildBehavioralState:MissingEpisodeStateVariables');

    if ~ismember('globalDecisionIndex', episodeState.Properties.VariableNames)
        episodeState.globalDecisionIndex = nan(height(episodeState), 1);
    end

    sortKey = double(episodeState.eventSeq);
    if any(isnan(sortKey))
        sortKey = double(episodeState.globalDecisionIndex);
    end
    [~, order] = sort(sortKey);
    episodeState = episodeState(order, :);

    actor = string(episodeState.actor);
    humanMask = actor == "human";
    if ~any(humanMask)
        behavioralState = table();
        return;
    end

    humanState = episodeState(humanMask, :);
    humanDecisionCount = height(humanState);

    episodeValues = double(humanState.episode);
    uniqueEpisodes = unique(episodeValues, 'stable');
    episodeOrdinal = zeros(humanDecisionCount, 1);
    decisionNumberWithinEpisode = zeros(humanDecisionCount, 1);
    episodeDecisionCount = zeros(humanDecisionCount, 1);
    episodeStartHumanDecisionNumber = zeros(humanDecisionCount, 1);
    episodeEndHumanDecisionNumber = zeros(humanDecisionCount, 1);
    nContributingEpisodesByDecisionNumberWithinEpisode = zeros(humanDecisionCount, 1);

    humanRowsByEpisode = cell(numel(uniqueEpisodes), 1);
    for i = 1:numel(uniqueEpisodes)
        episodeNumber = uniqueEpisodes(i);
        idx = find(episodeValues == episodeNumber);
        humanRowsByEpisode{i} = idx;
        episodeOrdinal(idx) = i;
        decisionNumberWithinEpisode(idx) = (1:numel(idx))';
        episodeDecisionCount(idx) = numel(idx);
        episodeStartHumanDecisionNumber(idx) = idx(1);
        episodeEndHumanDecisionNumber(idx) = idx(end);
    end

    for k = 1:humanDecisionCount
        nContributingEpisodesByDecisionNumberWithinEpisode(k) = sum(cellfun(@(episodeIdx) numel(episodeIdx) >= k, humanRowsByEpisode));
    end

    cumulativeHumanDecisionNumber = (1:humanDecisionCount)';
    block = double(humanState.block);
    phase = string(humanState.phase);
    activeRuleName = string(humanState.activeRuleName);
    activeRuleType = string(humanState.activeRuleType);
    trialWithinEpisode = double(humanState.trialWithinEpisode);
    chosenStimulusID = double(humanState.chosenStimulusID);
    chosenPositionID = double(humanState.chosenPositionID);
    chosenReward = logical(humanState.chosenReward);
    chosenRepeat = logical(humanState.chosenRepeat);
    chosenSatisfiesRule = logical(humanState.chosenSatisfiesRule);

    numberAvailableStimuli = zeros(humanDecisionCount, 1);
    numberAvailableMatchingStimuli = zeros(humanDecisionCount, 1);
    fractionAvailableMatchingRule = nan(humanDecisionCount, 1);
    advantageOverChance = nan(humanDecisionCount, 1);

    previousHumanReward = nan(humanDecisionCount, 1);
    previousAgentReward = nan(humanDecisionCount, 1);
    previousHumanRepeated = nan(humanDecisionCount, 1);
    previousAgentRepeated = nan(humanDecisionCount, 1);
    previousHumanSatisfiedRule = nan(humanDecisionCount, 1);
    previousAgentSatisfiedRule = nan(humanDecisionCount, 1);
    cumulativeHumanRewards = zeros(humanDecisionCount, 1);
    cumulativeAgentRewards = zeros(humanDecisionCount, 1);
    cumulativeHumanRuleSuccesses = zeros(humanDecisionCount, 1);
    cumulativeAgentRuleSuccesses = zeros(humanDecisionCount, 1);
    cumulativeHumanRepeatedChoices = zeros(humanDecisionCount, 1);
    cumulativeAgentRepeatedChoices = zeros(humanDecisionCount, 1);
    numberOfPreviousHumanChoices = zeros(humanDecisionCount, 1);
    numberOfPreviousAgentChoices = zeros(humanDecisionCount, 1);
    totalDecisionsSinceEpisodeStart = zeros(humanDecisionCount, 1);
    previousActor = repmat(string(missing), humanDecisionCount, 1);
    previousReward = nan(humanDecisionCount, 1);
    previousRepeated = nan(humanDecisionCount, 1);
    previousSatisfiedRule = nan(humanDecisionCount, 1);

    rowIndex = 0;
    currentEpisode = NaN;
    humanChoicesInEpisode = 0;
    agentChoicesInEpisode = 0;
    humanRewardsInEpisode = 0;
    agentRewardsInEpisode = 0;
    humanRuleSuccessesInEpisode = 0;
    agentRuleSuccessesInEpisode = 0;
    humanRepeatedChoicesInEpisode = 0;
    agentRepeatedChoicesInEpisode = 0;
    decisionsInEpisodeBeforeCurrent = 0;
    lastHumanReward = NaN;
    lastAgentReward = NaN;
    lastHumanRepeated = NaN;
    lastAgentRepeated = NaN;
    lastHumanSatisfiedRule = NaN;
    lastAgentSatisfiedRule = NaN;
    lastActor = string(missing);
    lastReward = NaN;
    lastRepeated = NaN;
    lastSatisfiedRule = NaN;

    for i = 1:height(episodeState)
        episodeNumber = double(episodeState.episode(i));
        if isnan(currentEpisode) || episodeNumber ~= currentEpisode
            currentEpisode = episodeNumber;
            humanChoicesInEpisode = 0;
            agentChoicesInEpisode = 0;
            humanRewardsInEpisode = 0;
            agentRewardsInEpisode = 0;
            humanRuleSuccessesInEpisode = 0;
            agentRuleSuccessesInEpisode = 0;
            humanRepeatedChoicesInEpisode = 0;
            agentRepeatedChoicesInEpisode = 0;
            decisionsInEpisodeBeforeCurrent = 0;
            lastHumanReward = NaN;
            lastAgentReward = NaN;
            lastHumanRepeated = NaN;
            lastAgentRepeated = NaN;
            lastHumanSatisfiedRule = NaN;
            lastAgentSatisfiedRule = NaN;
            lastActor = string(missing);
            lastReward = NaN;
            lastRepeated = NaN;
            lastSatisfiedRule = NaN;
        end

        isHuman = actor(i) == "human";
        reward = double(logical(episodeState.chosenReward(i)));
        repeated = double(logical(episodeState.chosenRepeat(i)));
        satisfiedRule = double(logical(episodeState.chosenSatisfiesRule(i)));

        if isHuman
            rowIndex = rowIndex + 1;
            previousHumanReward(rowIndex) = lastHumanReward;
            previousAgentReward(rowIndex) = lastAgentReward;
            previousHumanRepeated(rowIndex) = lastHumanRepeated;
            previousAgentRepeated(rowIndex) = lastAgentRepeated;
            previousHumanSatisfiedRule(rowIndex) = lastHumanSatisfiedRule;
            previousAgentSatisfiedRule(rowIndex) = lastAgentSatisfiedRule;
            previousActor(rowIndex) = lastActor;
            previousReward(rowIndex) = lastReward;
            previousRepeated(rowIndex) = lastRepeated;
            previousSatisfiedRule(rowIndex) = lastSatisfiedRule;

            cumulativeHumanRewards(rowIndex) = humanRewardsInEpisode;
            cumulativeAgentRewards(rowIndex) = agentRewardsInEpisode;
            cumulativeHumanRuleSuccesses(rowIndex) = humanRuleSuccessesInEpisode;
            cumulativeAgentRuleSuccesses(rowIndex) = agentRuleSuccessesInEpisode;
            cumulativeHumanRepeatedChoices(rowIndex) = humanRepeatedChoicesInEpisode;
            cumulativeAgentRepeatedChoices(rowIndex) = agentRepeatedChoicesInEpisode;
            numberOfPreviousHumanChoices(rowIndex) = humanChoicesInEpisode;
            numberOfPreviousAgentChoices(rowIndex) = agentChoicesInEpisode;
            totalDecisionsSinceEpisodeStart(rowIndex) = decisionsInEpisodeBeforeCurrent;

            availablePos = double(episodeState.availablePositionIDs{i});
            availableMatchPos = double(episodeState.availableMatchingPositionIDs{i});
            availableStim = double(episodeState.availableStimulusIDs{i});
            availableMatchStim = double(episodeState.availableMatchingStimulusIDs{i});

            if numel(availablePos) ~= numel(availableStim)
                error('af:buildBehavioralState:AvailableStimulusMismatch', ...
                    'Human decision row %d has mismatched available position and stimulus lists.', i);
            end
            if numel(availableMatchPos) ~= numel(availableMatchStim)
                error('af:buildBehavioralState:MatchingStimulusMismatch', ...
                    'Human decision row %d has mismatched rule-matching available lists.', i);
            end
            if isempty(availablePos)
                error('af:buildBehavioralState:NoAvailableStimuli', ...
                    'Human decision row %d has no available stimuli.', i);
            end

            numberAvailableStimuli(rowIndex) = numel(availablePos);
            numberAvailableMatchingStimuli(rowIndex) = numel(availableMatchPos);
            fractionAvailableMatchingRule(rowIndex) = numberAvailableMatchingStimuli(rowIndex) / numberAvailableStimuli(rowIndex);
            advantageOverChance(rowIndex) = double(chosenSatisfiesRule(rowIndex)) - fractionAvailableMatchingRule(rowIndex);

            if ~any(chosenPositionID(rowIndex) == availablePos)
                error('af:buildBehavioralState:ChosenPositionNotAvailable', ...
                    'Human decision row %d chose position %g, which is not in availablePositionIDs.', ...
                    i, chosenPositionID(rowIndex));
            end
            chosenAvailableIndex = find(availablePos == chosenPositionID(rowIndex), 1, 'first');
            if isempty(chosenAvailableIndex) || availableStim(chosenAvailableIndex) ~= chosenStimulusID(rowIndex)
                error('af:buildBehavioralState:ChosenStimulusMismatch', ...
                    'Human decision row %d has a chosen stimulus that does not match the available-state mapping.', i);
            end

            humanChoicesInEpisode = humanChoicesInEpisode + 1;
            humanRewardsInEpisode = humanRewardsInEpisode + reward;
            humanRuleSuccessesInEpisode = humanRuleSuccessesInEpisode + satisfiedRule;
            humanRepeatedChoicesInEpisode = humanRepeatedChoicesInEpisode + repeated;
            decisionsInEpisodeBeforeCurrent = decisionsInEpisodeBeforeCurrent + 1;
        else
            agentChoicesInEpisode = agentChoicesInEpisode + 1;
            agentRewardsInEpisode = agentRewardsInEpisode + reward;
            agentRuleSuccessesInEpisode = agentRuleSuccessesInEpisode + satisfiedRule;
            agentRepeatedChoicesInEpisode = agentRepeatedChoicesInEpisode + repeated;
            decisionsInEpisodeBeforeCurrent = decisionsInEpisodeBeforeCurrent + 1;
        end

        if isHuman
            lastHumanReward = reward;
            lastHumanRepeated = repeated;
            lastHumanSatisfiedRule = satisfiedRule;
        else
            lastAgentReward = reward;
            lastAgentRepeated = repeated;
            lastAgentSatisfiedRule = satisfiedRule;
        end
        lastActor = actor(i);
        lastReward = reward;
        lastRepeated = repeated;
        lastSatisfiedRule = satisfiedRule;
    end

    behavioralState = table();
    if ismember('decisionID', humanState.Properties.VariableNames)
        behavioralState.decisionID = double(humanState.decisionID);
    end
    if ismember('globalDecisionIndex', humanState.Properties.VariableNames)
        behavioralState.globalDecisionIndex = double(humanState.globalDecisionIndex);
    end
    behavioralState.cumulativeHumanDecisionNumber = cumulativeHumanDecisionNumber;
    behavioralState.episode = episodeValues;
    behavioralState.episodeOrdinal = episodeOrdinal;
    behavioralState.decisionNumberWithinEpisode = decisionNumberWithinEpisode;
    behavioralState.episodeDecisionCount = episodeDecisionCount;
    behavioralState.episodeStartHumanDecisionNumber = episodeStartHumanDecisionNumber;
    behavioralState.episodeEndHumanDecisionNumber = episodeEndHumanDecisionNumber;
    behavioralState.nContributingEpisodesByDecisionNumberWithinEpisode = nContributingEpisodesByDecisionNumberWithinEpisode;
    behavioralState.block = block;
    behavioralState.phase = phase;
    behavioralState.activeRuleName = activeRuleName;
    behavioralState.activeRuleType = activeRuleType;
    behavioralState.trialWithinEpisode = trialWithinEpisode;
    behavioralState.totalDecisionsSinceEpisodeStart = totalDecisionsSinceEpisodeStart;
    behavioralState.numberAvailableStimuli = numberAvailableStimuli;
    behavioralState.numberAvailableMatchingStimuli = numberAvailableMatchingStimuli;
    behavioralState.fractionAvailableMatchingRule = fractionAvailableMatchingRule;
    behavioralState.chosenStimulusID = chosenStimulusID;
    behavioralState.chosenPositionID = chosenPositionID;
    behavioralState.chosenReward = chosenReward;
    behavioralState.chosenRepeat = chosenRepeat;
    behavioralState.chosenSatisfiesRule = chosenSatisfiesRule;
    behavioralState.advantageOverChance = advantageOverChance;
    behavioralState.previousHumanReward = previousHumanReward;
    behavioralState.previousAgentReward = previousAgentReward;
    behavioralState.previousHumanRepeated = previousHumanRepeated;
    behavioralState.previousAgentRepeated = previousAgentRepeated;
    behavioralState.previousHumanSatisfiedRule = previousHumanSatisfiedRule;
    behavioralState.previousAgentSatisfiedRule = previousAgentSatisfiedRule;
    behavioralState.cumulativeHumanRewards = cumulativeHumanRewards;
    behavioralState.cumulativeAgentRewards = cumulativeAgentRewards;
    behavioralState.cumulativeHumanRuleSuccesses = cumulativeHumanRuleSuccesses;
    behavioralState.cumulativeAgentRuleSuccesses = cumulativeAgentRuleSuccesses;
    behavioralState.cumulativeHumanRepeatedChoices = cumulativeHumanRepeatedChoices;
    behavioralState.cumulativeAgentRepeatedChoices = cumulativeAgentRepeatedChoices;
    behavioralState.numberOfPreviousHumanChoices = numberOfPreviousHumanChoices;
    behavioralState.numberOfPreviousAgentChoices = numberOfPreviousAgentChoices;
    behavioralState.previousActor = previousActor;
    behavioralState.previousReward = previousReward;
    behavioralState.previousRepeated = previousRepeated;
    behavioralState.previousSatisfiedRule = previousSatisfiedRule;
    behavioralState.availablePositionIDs = humanState.availablePositionIDs;
    behavioralState.availableStimulusIDs = humanState.availableStimulusIDs;
    behavioralState.availableMatchingPositionIDs = humanState.availableMatchingPositionIDs;
    behavioralState.availableMatchingStimulusIDs = humanState.availableMatchingStimulusIDs;

    if ismember('sessionID', humanState.Properties.VariableNames)
        behavioralState.sessionID = humanState.sessionID;
    end
    if ismember('participantID', humanState.Properties.VariableNames)
        behavioralState.participantID = humanState.participantID;
    end
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end