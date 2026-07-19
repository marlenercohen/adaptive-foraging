function episodeState = reconstructEpisodeState(trials, session, stimuli, rules)
%af.reconstructEpisodeState Reconstruct complete objective episode state.
%   EPISODESTATE = af.reconstructEpisodeState(TRIALS, SESSION, STIMULI, RULES)
%   returns one row per human or agent decision describing the task state
%   immediately before that decision.
%
%   This function is model-agnostic. It performs no behavioral analyses and
%   computes no learning metrics. It reuses existing canonical/state helpers
%   and the shared board transition logic used elsewhere in the analysis
%   pipeline.

    if nargin < 4
        error('af:reconstructEpisodeState:MissingInput', ...
            'trials, session, stimuli, and rules are required.');
    end
    if ~istable(trials)
        error('af:reconstructEpisodeState:InvalidTrialsType', 'trials must be a table.');
    end
    if ~isstruct(session)
        error('af:reconstructEpisodeState:InvalidSessionType', 'session must be a struct returned by loadSession().');
    end
    if ~istable(stimuli)
        error('af:reconstructEpisodeState:InvalidStimuliType', 'stimuli must be a table.');
    end
    if ~istable(rules)
        error('af:reconstructEpisodeState:InvalidRulesType', 'rules must be a table.');
    end

    canonicalState = af.buildCanonicalState(trials, stimuli, rules, session);
    decisionState = af.reconstructDecisionState(canonicalState);
    availableBoard = af.reconstructAvailableBoard(canonicalState, decisionState);

    assertTableVariables(availableBoard, {
        'decisionID','globalDecisionIndex','episode','positionID','stimulusID'
    }, 'af:reconstructEpisodeState:MissingAvailableBoardVariables');

    eventLog = getStructArrayField(session, 'eventLog');
    if isempty(eventLog)
        error('af:reconstructEpisodeState:MissingEventLog', ...
            'session.eventLog is required to reconstruct human and agent decision sequence.');
    end

    moveEvents = selectMoveEvents(eventLog);
    if isempty(moveEvents)
        episodeState = table();
        return;
    end

    boardColumnCount = resolveBoardColumnCount();

    stimuliIndex = buildStimulusIndex(stimuli);
    rulesIndex = buildRuleIndex(rules);
    humanAvailableIndex = buildHumanAvailableIndex(availableBoard);

    [sortedDecisionIds, order] = sort(double(decisionState.decisionID)); %#ok<ASGLU>
    decisionState = decisionState(order, :);
    trials = canonicalState.facts.trials(order, :);

    humanDecisionIds = double(decisionState.decisionID);
    humanDecisionPointer = 0;

    rows = repmat(makeEpisodeStateRow(), 0, 1);

    currentEpisode = NaN;
    currentState = struct();
    histories = makeEmptyHistories();
    lastHumanPosition = NaN;
    lastAgentPosition = NaN;
    lastHumanStimulusID = NaN;
    lastAgentStimulusID = NaN;

    for i = 1:numel(moveEvents)
        event = moveEvents(i);
        eventType = string(getStructField(event, 'type', ""));
        eventData = getStructField(event, 'data', struct());

        actor = string(getStructField(eventData, 'actor', ""));
        if strlength(actor) == 0
            if eventType == "human_move"
                actor = "human";
            elseif eventType == "agent_move"
                actor = "agent";
            end
        end

        episodeNumber = getNumericField(eventData, 'episodeNumber', NaN);
        if isnan(episodeNumber)
            error('af:reconstructEpisodeState:MissingEpisodeNumber', ...
                'Move event seq %g is missing data.episodeNumber.', getNumericField(event, 'seq', NaN));
        end

        if isnan(currentEpisode) || episodeNumber ~= currentEpisode
            currentEpisode = episodeNumber;
            [currentState, humanDecisionIdsInEpisode] = seedEpisodeFromCanonical(canonicalState, decisionState, currentEpisode);
            histories = makeEmptyHistories();
            lastHumanPosition = NaN;
            lastAgentPosition = NaN;
            lastHumanStimulusID = NaN;
            lastAgentStimulusID = NaN;
            humanDecisionPointer = 0;
        end

        ruleName = string(getStructField(eventData, 'ruleFile', ""));
        if strlength(ruleName) == 0
            error('af:reconstructEpisodeState:MissingRuleFile', ...
                'Move event seq %g in episode %g is missing data.ruleFile.', ...
                getNumericField(event, 'seq', NaN), currentEpisode);
        end
        ruleRow = getRuleRow(ruleName, rulesIndex, rules);

        positionID = getNumericField(eventData, 'positionID', NaN);
        stimulusID = getNumericField(eventData, 'stimulusID', NaN);
        reward = getLogicalField(eventData, 'reward', false);
        repeat = getLogicalField(eventData, 'repeat', false);
        moveNumber = getNumericField(eventData, 'moveNumber', NaN);
        blockNumber = getNumericField(eventData, 'blockNumber', NaN);
        phaseName = string(getStructField(eventData, 'phaseName', ""));
        eventSeq = getNumericField(event, 'seq', NaN);

        availabilityMask = ~currentState.resolved;
        boardPositionIDs = currentState.positionIDs(:)';
        boardStimulusIDsByPosition = currentState.stimulusIDs(:)';
        availablePositionIDs = boardPositionIDs(availabilityMask(:)');
        availableStimulusIDs = boardStimulusIDsByPosition(availabilityMask(:)');

        if actor == "human"
            humanDecisionPointer = humanDecisionPointer + 1;
            if humanDecisionPointer > numel(humanDecisionIdsInEpisode)
                error('af:reconstructEpisodeState:HumanDecisionCountMismatch', ...
                    'Episode %g contains more human_move events than trial rows.', currentEpisode);
            end
            decisionID = humanDecisionIdsInEpisode(humanDecisionPointer);
            decisionRow = decisionState(double(decisionState.decisionID) == decisionID, :);
            if isempty(decisionRow)
                error('af:reconstructEpisodeState:MissingDecisionStateRow', ...
                    'No decisionState row found for decisionID %g.', decisionID);
            end
            validateHumanBoardAgainstAvailableIndex(currentState, humanAvailableIndex, decisionID, currentEpisode);

            previousOtherPosition = lastAgentPosition;
            previousOtherStimulus = lastAgentStimulusID;
            globalDecisionIndex = double(decisionRow.globalDecisionIndex);
        else
            decisionID = NaN;
            globalDecisionIndex = NaN;
            previousOtherPosition = lastHumanPosition;
            previousOtherStimulus = lastHumanStimulusID; %#ok<NASGU>
        end

        [availableMatchesMask, availableMatchingPositionIDs, availableMatchingStimulusIDs] = ...
            evaluateAvailableStimuli(currentState, availablePositionIDs, availableStimulusIDs, ruleRow, previousOtherPosition, boardColumnCount, stimuliIndex, stimuli);

        chosenStimulusRow = getStimulusRow(stimulusID, stimuliIndex, stimuli);
        chosenSatisfiesRule = evaluateRuleSatisfied(ruleRow, chosenStimulusRow, positionID, previousOtherPosition, boardColumnCount);

        repeatedOwnLocation = false;
        repeatedOtherLocation = false;
        if actor == "human"
            repeatedOwnLocation = any(histories.humanChoicePositions == positionID);
            repeatedOtherLocation = any(histories.agentChoicePositions == positionID);
        elseif actor == "agent"
            repeatedOwnLocation = any(histories.agentChoicePositions == positionID);
            repeatedOtherLocation = any(histories.humanChoicePositions == positionID);
        end

        if repeat ~= (repeatedOwnLocation || repeatedOtherLocation)
            error('af:reconstructEpisodeState:RepeatFlagMismatch', ...
                ['%s move at seq %g in episode %g has repeat=%d, but reconstructed ', ...
                 'history implies repeat=%d.'], ...
                actor, eventSeq, currentEpisode, repeat, (repeatedOwnLocation || repeatedOtherLocation));
        end

        row = makeEpisodeStateRow();
        row.decisionID = decisionID;
        row.globalDecisionIndex = globalDecisionIndex;
        row.eventSeq = eventSeq;
        row.block = blockNumber;
        row.phase = phaseName;
        row.episode = currentEpisode;
        row.trialWithinEpisode = moveNumber;
        row.actor = actor;
        row.boardColumnCount = boardColumnCount;

        row.activeRuleName = string(ruleRow.ruleName);
        row.activeRuleType = string(ruleRow.ruleType);
        row.activeRuleFeature = string(ruleRow.feature);
        row.activeRuleOperator = string(ruleRow.operator);
        row.activeRuleValue = double(ruleRow.value);
        row.activeRuleMinimumDistance = double(ruleRow.minimumDistance);

        row.boardPositionIDs = {boardPositionIDs};
        row.boardStimulusIDsByPosition = {boardStimulusIDsByPosition};
        row.availablePositionIDs = {availablePositionIDs};
        row.availableStimulusIDs = {availableStimulusIDs};
        row.availabilityMask = {availabilityMask(:)'};
        row.availableMatchesRuleMask = {availableMatchesMask};
        row.availableMatchingPositionIDs = {availableMatchingPositionIDs};
        row.availableMatchingStimulusIDs = {availableMatchingStimulusIDs};

        row.humanChoicePositionsBefore = {histories.humanChoicePositions};
        row.humanChoiceStimulusIDsBefore = {histories.humanChoiceStimulusIDs};
        row.agentChoicePositionsBefore = {histories.agentChoicePositions};
        row.agentChoiceStimulusIDsBefore = {histories.agentChoiceStimulusIDs};
        row.rewardedHumanChoicePositionsBefore = {histories.rewardedHumanChoicePositions};
        row.rewardedHumanChoiceStimulusIDsBefore = {histories.rewardedHumanChoiceStimulusIDs};
        row.rewardedAgentChoicePositionsBefore = {histories.rewardedAgentChoicePositions};
        row.rewardedAgentChoiceStimulusIDsBefore = {histories.rewardedAgentChoiceStimulusIDs};
        row.repeatedHumanLocationsBefore = {histories.repeatedHumanLocations};
        row.repeatedAgentLocationsBefore = {histories.repeatedAgentLocations};

        row.previousOtherPosition = previousOtherPosition;
        row.chosenStimulusID = stimulusID;
        row.chosenPositionID = positionID;
        row.chosenReward = reward;
        row.chosenSatisfiesRule = chosenSatisfiesRule;
        row.chosenRepeat = repeat;
        row.chosenRepeatedOwnLocation = repeatedOwnLocation;
        row.chosenRepeatedOtherLocation = repeatedOtherLocation;

        rows(end + 1, 1) = row; %#ok<AGROW>

        currentState = af.applyBoardTransition(currentState, positionID, stimulusID, repeat, actor, eventSeq, currentEpisode);

        if actor == "human"
            histories.humanChoicePositions(end + 1, 1) = positionID; %#ok<AGROW>
            histories.humanChoiceStimulusIDs(end + 1, 1) = stimulusID; %#ok<AGROW>
            lastHumanPosition = positionID;
            lastHumanStimulusID = stimulusID;
            if reward
                histories.rewardedHumanChoicePositions(end + 1, 1) = positionID; %#ok<AGROW>
                histories.rewardedHumanChoiceStimulusIDs(end + 1, 1) = stimulusID; %#ok<AGROW>
            end
            if repeat
                histories.repeatedHumanLocations(end + 1, 1) = positionID; %#ok<AGROW>
            end
        else
            histories.agentChoicePositions(end + 1, 1) = positionID; %#ok<AGROW>
            histories.agentChoiceStimulusIDs(end + 1, 1) = stimulusID; %#ok<AGROW>
            lastAgentPosition = positionID;
            lastAgentStimulusID = stimulusID;
            if reward
                histories.rewardedAgentChoicePositions(end + 1, 1) = positionID; %#ok<AGROW>
                histories.rewardedAgentChoiceStimulusIDs(end + 1, 1) = stimulusID; %#ok<AGROW>
            end
            if repeat
                histories.repeatedAgentLocations(end + 1, 1) = positionID; %#ok<AGROW>
            end
        end
    end

    episodeState = struct2table(rows);
    episodeState = sortrows(episodeState, {'eventSeq'});
end

function moveEvents = selectMoveEvents(eventLog)
    keep = false(numel(eventLog), 1);
    seq = nan(numel(eventLog), 1);
    for i = 1:numel(eventLog)
        eventType = string(getStructField(eventLog(i), 'type', ""));
        keep(i) = (eventType == "human_move") || (eventType == "agent_move");
        seq(i) = getNumericField(eventLog(i), 'seq', NaN);
    end
    moveEvents = eventLog(keep);
    seq = seq(keep);
    [~, order] = sort(seq);
    moveEvents = moveEvents(order);
end

function [state, decisionIdsInEpisode] = seedEpisodeFromCanonical(canonicalState, decisionState, episodeNumber)
    boardState = canonicalState.facts.boardState;
    trials = canonicalState.facts.trials;

    episodeDecisionRows = find(double(trials.episode) == episodeNumber);
    if isempty(episodeDecisionRows)
        error('af:reconstructEpisodeState:MissingEpisodeTrials', ...
            'No trial rows found for episode %g.', episodeNumber);
    end

    firstDecisionId = double(trials.decisionID(episodeDecisionRows(1)));
    seedRows = boardState(double(boardState.decisionID) == firstDecisionId, :);
    if isempty(seedRows)
        error('af:reconstructEpisodeState:MissingEpisodeBoardSeed', ...
            'No boardState seed rows found for first decisionID %g in episode %g.', ...
            firstDecisionId, episodeNumber);
    end

    positionIds = double(seedRows.positionID);
    maxPosition = max(positionIds);
    expectedPositions = (0:maxPosition)';
    if numel(positionIds) ~= numel(expectedPositions) || ~all(sort(positionIds) == expectedPositions)
        error('af:reconstructEpisodeState:NonContiguousEpisodeBoard', ...
            'Episode %g seed snapshot does not contain a contiguous board layout.', episodeNumber);
    end

    state = struct();
    state.positionIDs = expectedPositions;
    state.stimulusIDs = nan(numel(expectedPositions), 1);
    state.resolved = false(numel(expectedPositions), 1);
    for i = 1:height(seedRows)
        pos = double(seedRows.positionID(i));
        state.stimulusIDs(pos + 1) = double(seedRows.stimulusID(i));
        state.resolved(pos + 1) = logical(seedRows.resolved(i));
    end

    decisionIdsInEpisode = double(decisionState.decisionID(double(decisionState.episode) == episodeNumber));
end

function validateHumanBoardAgainstAvailableIndex(state, availableIndex, decisionID, episodeNumber)
    key = numericKey(decisionID);
    if ~isKey(availableIndex, key)
        error('af:reconstructEpisodeState:MissingHumanAvailableBoard', ...
            'No reconstructed available-board rows found for human decisionID %g in episode %g.', ...
            decisionID, episodeNumber);
    end

    rows = availableIndex(key);
    availableMask = ~state.resolved;
    actualPositions = state.positionIDs(availableMask);
    actualStimuli = state.stimulusIDs(availableMask);

    expectedPositions = double(rows.positionID);
    expectedStimuli = double(rows.stimulusID);
    [expectedPositions, order] = sort(expectedPositions);
    expectedStimuli = expectedStimuli(order);

    if ~isequal(actualPositions(:), expectedPositions(:)) || ~isequal(actualStimuli(:), expectedStimuli(:))
        error('af:reconstructEpisodeState:HumanBoardMismatch', ...
            ['Reconstructed board before human decisionID %g in episode %g does not ', ...
             'match af.reconstructAvailableBoard output.'], ...
            decisionID, episodeNumber);
    end
end

function [mask, matchingPositions, matchingStimuli] = evaluateAvailableStimuli(state, availablePositions, availableStimuli, ruleRow, previousOtherPosition, boardColumnCount, stimuliIndex, stimuli)
    mask = false(1, numel(availablePositions));
    for i = 1:numel(availablePositions)
        stimRow = getStimulusRow(availableStimuli(i), stimuliIndex, stimuli);
        mask(i) = evaluateRuleSatisfied(ruleRow, stimRow, availablePositions(i), previousOtherPosition, boardColumnCount);
    end
    matchingPositions = availablePositions(mask);
    matchingStimuli = availableStimuli(mask);
end

function stimRow = getStimulusRow(stimulusID, stimuliIndex, stimuli)
    key = numericKey(stimulusID);
    if ~isKey(stimuliIndex, key)
        error('af:reconstructEpisodeState:UnknownStimulusID', ...
            'Stimulus ID %g is missing from the stimuli table.', stimulusID);
    end
    stimRow = stimuli(stimuliIndex(key), :);
end

function ruleRow = getRuleRow(ruleName, rulesIndex, rules)
    key = char(string(ruleName));
    if ~isKey(rulesIndex, key)
        error('af:reconstructEpisodeState:UnknownRule', ...
            'Active rule "%s" is missing from the rules table.', key);
    end
    ruleRow = rules(rulesIndex(key), :);
end

function idx = buildStimulusIndex(stimuli)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'double');
    values = double(stimuli.stimulusID);
    for i = 1:height(stimuli)
        idx(numericKey(values(i))) = i;
    end
end

function idx = buildRuleIndex(rules)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'double');
    names = string(rules.ruleName);
    for i = 1:height(rules)
        idx(char(names(i))) = i;
    end
end

function idx = buildHumanAvailableIndex(availableBoard)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'any');
    decisionIds = unique(double(availableBoard.decisionID));
    for i = 1:numel(decisionIds)
        did = decisionIds(i);
        idx(numericKey(did)) = availableBoard(double(availableBoard.decisionID) == did, :);
    end
end

function tf = evaluateRuleSatisfied(ruleRow, stimulusRow, positionID, previousOtherPosition, boardColumnCount)
    ruleType = string(ruleRow.ruleType);

    switch ruleType
        case "feature"
            featureName = string(ruleRow.feature);
            operator = string(ruleRow.operator);
            targetValue = double(ruleRow.value(1));

            if ~ismember(char(featureName), stimulusRow.Properties.VariableNames)
                error('af:reconstructEpisodeState:MissingStimulusFeature', ...
                    'Stimulus table is missing required feature column "%s".', char(featureName));
            end

            actualValue = stimulusRow.(char(featureName));
            actualValue = double(actualValue(1));
            tf = evaluateOperator(actualValue, operator, targetValue);

        case "distance-from-agent"
            if isnan(previousOtherPosition)
                tf = false;
                return;
            end
            minimumDistance = double(ruleRow.minimumDistance(1));
            distance = computeManhattanDistance(positionID, previousOtherPosition, boardColumnCount);
            tf = distance >= minimumDistance;

        otherwise
            error('af:reconstructEpisodeState:UnsupportedRuleType', ...
                'Unsupported rule type "%s".', char(ruleType));
    end
end

function tf = evaluateOperator(actual, operator, target)
    switch char(operator)
        case '=='
            tf = actual == target;
        case '~='
            tf = actual ~= target;
        case '>'
            tf = actual > target;
        case '<'
            tf = actual < target;
        case '>='
            tf = actual >= target;
        case '<='
            tf = actual <= target;
        otherwise
            error('af:reconstructEpisodeState:UnsupportedOperator', ...
                'Unsupported rule operator "%s".', char(operator));
    end
end

function d = computeManhattanDistance(positionA, positionB, boardColumnCount)
    cols = floor(boardColumnCount);
    rowA = floor(positionA / cols);
    colA = mod(positionA, cols);
    rowB = floor(positionB / cols);
    colB = mod(positionB, cols);
    d = abs(rowA - rowB) + abs(colA - colB);
end

function boardColumnCount = resolveBoardColumnCount()
    % Match the existing MATLAB runtime assumption used by buildTrialTable.
    boardColumnCount = 5;
end

function histories = makeEmptyHistories()
    histories = struct( ...
        'humanChoicePositions', zeros(0, 1), ...
        'humanChoiceStimulusIDs', zeros(0, 1), ...
        'agentChoicePositions', zeros(0, 1), ...
        'agentChoiceStimulusIDs', zeros(0, 1), ...
        'rewardedHumanChoicePositions', zeros(0, 1), ...
        'rewardedHumanChoiceStimulusIDs', zeros(0, 1), ...
        'rewardedAgentChoicePositions', zeros(0, 1), ...
        'rewardedAgentChoiceStimulusIDs', zeros(0, 1), ...
        'repeatedHumanLocations', zeros(0, 1), ...
        'repeatedAgentLocations', zeros(0, 1) ...
    );
end

function row = makeEpisodeStateRow()
    row = struct( ...
        'decisionID', NaN, ...
        'globalDecisionIndex', NaN, ...
        'eventSeq', NaN, ...
        'block', NaN, ...
        'phase', "", ...
        'episode', NaN, ...
        'trialWithinEpisode', NaN, ...
        'actor', "", ...
        'boardColumnCount', NaN, ...
        'activeRuleName', "", ...
        'activeRuleType', "", ...
        'activeRuleFeature', "", ...
        'activeRuleOperator', "", ...
        'activeRuleValue', NaN, ...
        'activeRuleMinimumDistance', NaN, ...
        'boardPositionIDs', {zeros(1, 0)}, ...
        'boardStimulusIDsByPosition', {zeros(1, 0)}, ...
        'availablePositionIDs', {zeros(1, 0)}, ...
        'availableStimulusIDs', {zeros(1, 0)}, ...
        'availabilityMask', {false(1, 0)}, ...
        'availableMatchesRuleMask', {false(1, 0)}, ...
        'availableMatchingPositionIDs', {zeros(1, 0)}, ...
        'availableMatchingStimulusIDs', {zeros(1, 0)}, ...
        'humanChoicePositionsBefore', {zeros(1, 0)}, ...
        'humanChoiceStimulusIDsBefore', {zeros(1, 0)}, ...
        'agentChoicePositionsBefore', {zeros(1, 0)}, ...
        'agentChoiceStimulusIDsBefore', {zeros(1, 0)}, ...
        'rewardedHumanChoicePositionsBefore', {zeros(1, 0)}, ...
        'rewardedHumanChoiceStimulusIDsBefore', {zeros(1, 0)}, ...
        'rewardedAgentChoicePositionsBefore', {zeros(1, 0)}, ...
        'rewardedAgentChoiceStimulusIDsBefore', {zeros(1, 0)}, ...
        'repeatedHumanLocationsBefore', {zeros(1, 0)}, ...
        'repeatedAgentLocationsBefore', {zeros(1, 0)}, ...
        'previousOtherPosition', NaN, ...
        'chosenStimulusID', NaN, ...
        'chosenPositionID', NaN, ...
        'chosenReward', false, ...
        'chosenSatisfiesRule', false, ...
        'chosenRepeat', false, ...
        'chosenRepeatedOwnLocation', false, ...
        'chosenRepeatedOtherLocation', false ...
    );
end

function value = numericKey(v)
    value = sprintf('%.15g', double(v));
end

function raw = getStructField(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName)
        raw = s.(fieldName);
    else
        raw = defaultValue;
    end
end

function events = getStructArrayField(s, fieldName)
    events = struct([]);
    if isstruct(s) && isfield(s, fieldName)
        raw = s.(fieldName);
        if isstruct(raw)
            events = raw;
        end
    end
end

function value = getNumericField(s, fieldName, defaultValue)
    value = defaultValue;
    if ~isstruct(s) || ~isfield(s, fieldName)
        return;
    end
    raw = s.(fieldName);
    if isnumeric(raw) || islogical(raw)
        if ~isempty(raw)
            value = double(raw(1));
        end
        return;
    end
    if ischar(raw) || isstring(raw)
        parsed = str2double(string(raw));
        if ~isnan(parsed)
            value = parsed;
        end
    end
end

function value = getLogicalField(s, fieldName, defaultValue)
    value = defaultValue;
    if ~isstruct(s) || ~isfield(s, fieldName)
        return;
    end
    raw = s.(fieldName);
    if islogical(raw)
        if ~isempty(raw)
            value = logical(raw(1));
        end
        return;
    end
    if isnumeric(raw)
        if ~isempty(raw)
            value = logical(raw(1) ~= 0);
        end
        return;
    end
    if ischar(raw) || isstring(raw)
        str = lower(strtrim(string(raw)));
        if any(strcmp(str, ["true","1","yes"]))
            value = true;
        elseif any(strcmp(str, ["false","0","no"]))
            value = false;
        end
    end
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
