function trials = buildTrialTable(session, stimuli, rules, boardColumnCount)
%BUILDTRIALTABLE Build one analysis row per human decision.
%   TRIALS = BUILDTRIALTABLE(SESSION, STIMULI, RULES) parses one loaded
%   session (from LOADSESSION), joins stimulus metadata (from
%   BUILDSTIMULUSTABLE) and active rule metadata (from BUILDRULETABLE),
%   and returns one table row per HUMAN decision.
%
%   TRIALS = BUILDTRIALTABLE(SESSION, STIMULI, RULES, BOARDCOLUMNCOUNT)
%   sets the board column count used for Manhattan distance calculations.
%   If BOARDCOLUMNCOUNT is omitted or empty, it defaults to 5.
%
%   Current experiment design uses a fixed 4x5 board (20 positions,
%   numbered 0-19 in the event log), so the default BOARDCOLUMNCOUNT=5
%   matches task geometry.
%
%   The parser walks SESSION.EVENTLOG exactly once while maintaining a
%   reconstruction state. If required information cannot be reconstructed
%   from the session, this function throws an informative error.

    validateInputs(session, stimuli, rules);

    if nargin < 4 || isempty(boardColumnCount)
        boardColumnCount = 5;
    end
    boardColumnCount = asNumber(boardColumnCount, NaN);
    if isnan(boardColumnCount) || ~isfinite(boardColumnCount) || boardColumnCount <= 0
        error('buildTrialTable:InvalidBoardColumnCount', ...
            'boardColumnCount must be a positive numeric scalar.');
    end

    events = afField(session, 'eventLog', struct([]));
    if isempty(events)
        trials = emptyTrialsTable();
        return;
    end

    stimIndex = buildNumericIndex(stimuli, 'stimulusID');
    ruleIndex = buildStringIndex(rules, 'ruleName');

    rows = repmat(defaultTrialRow(), 0, 1);
    state = initialState();

    for i = 1:numel(events)
        event = events(i);
        eventType = string(afField(event, 'type', ""));
        eventData = afField(event, 'data', struct());
        if ~isstruct(eventData)
            eventData = struct();
        end

        switch eventType
            case "stimulus_selection"
                state.lastStimulusSelection = eventData;

            case "repeated_stimulus_selection"
                state.lastRepeatedSelection = eventData;

            case "episode_start"
                if state.hasPendingHumanRow
                    rows(end + 1, 1) = finalizePendingHumanRow(state.pendingHumanRow, state); %#ok<AGROW>
                    state.hasPendingHumanRow = false;
                end

                state.currentEpisode = asNumber(afField(eventData, 'episodeNumber', state.currentEpisode), state.currentEpisode);
                state.currentBlock = asNumber(afField(eventData, 'blockNumber', state.currentBlock), state.currentBlock);
                state.currentPhase = asString(afField(eventData, 'phaseName', state.currentPhase));
                state.currentRule = asString(afField(eventData, 'ruleFile', state.currentRule));

                state.trialWithinEpisode = 0;

                state.humanEpisodeScore = 0;
                state.agentEpisodeScore = 0;
                state.rewardsRemaining = asNumber(afField(eventData, 'rewardsAvailable', NaN), NaN);

                state.previousAgentChoice = emptyChoice();
                state.previousHumanChoice = emptyChoice();

                state.selectedByHuman = zeros(0, 1);
                state.selectedByAgent = zeros(0, 1);

                state.lastStimulusSelection = struct();
                state.lastRepeatedSelection = struct();
                state.lastMove = struct();
                state.seenEpisodeStart = true;

            case "rule_change"
                toRule = asString(afField(eventData, 'toRuleFile', ""));
                if strlength(toRule) > 0
                    state.currentRule = toRule;
                end

            case "score_update"
                state.humanEpisodeScore = asNumber(afField(eventData, 'humanScore', state.humanEpisodeScore), state.humanEpisodeScore);
                state.agentEpisodeScore = asNumber(afField(eventData, 'agentScore', state.agentEpisodeScore), state.agentEpisodeScore);
                state.humanTotalScore = asNumber(afField(eventData, 'humanTotalScore', state.humanTotalScore), state.humanTotalScore);
                state.agentTotalScore = asNumber(afField(eventData, 'agentTotalScore', state.agentTotalScore), state.agentTotalScore);
                state.rewardsRemaining = asNumber(afField(eventData, 'rewardsRemaining', state.rewardsRemaining), state.rewardsRemaining);

                if state.hasPendingHumanRow
                    rows(end + 1, 1) = finalizePendingHumanRow(state.pendingHumanRow, state); %#ok<AGROW>
                    state.hasPendingHumanRow = false;
                end

            case "reward_delivered"
                state = validateOptionalRewardDelivered(state, eventData);

            case "agent_move"
                state.seenAgentMove = true;
                validateOptionalMoveConsistency(eventData, 'agent', state);
                choice = parseMoveChoice(eventData, 'agent', state, stimIndex, stimuli, ruleIndex, rules, boardColumnCount);

                state.previousAgentChoice = choice;
                state.lastMove = eventData;

                if ~choice.repeat
                    state.selectedByAgent = addUnique(state.selectedByAgent, choice.position);
                end
                state.lastStimulusSelection = struct();
                state.lastRepeatedSelection = struct();

            case "human_move"
                state.seenHumanMove = true;
                validateOptionalMoveConsistency(eventData, 'human', state);
                if state.hasPendingHumanRow
                    rows(end + 1, 1) = finalizePendingHumanRow(state.pendingHumanRow, state); %#ok<AGROW>
                    state.hasPendingHumanRow = false;
                end

                choice = parseMoveChoice(eventData, 'human', state, stimIndex, stimuli, ruleIndex, rules, boardColumnCount);

                moveNumber = asNumber(afField(eventData, 'moveNumber', NaN), NaN);
                if ~isnan(moveNumber)
                    state.trialWithinEpisode = moveNumber;
                else
                    state.trialWithinEpisode = state.trialWithinEpisode + 1;
                end
                state.humanSelectionNumber = state.humanSelectionNumber + 1;

                row = defaultTrialRow();

                % Experiment structure
                row.block = state.currentBlock;
                row.phase = state.currentPhase;
                row.episode = state.currentEpisode;
                row.trialWithinEpisode = state.trialWithinEpisode;
                row.humanSelectionNumber = state.humanSelectionNumber;

                % Active rule
                activeRule = getActiveRuleRow(state.currentRule, ruleIndex, rules);
                row.ruleName = asString(activeRule.ruleName);
                row.ruleType = asString(activeRule.ruleType);
                row.feature = asString(activeRule.feature);
                row.operator = asString(activeRule.operator);
                row.value = activeRule.value;
                row.minimumDistance = activeRule.minimumDistance;

                % Human choice and joined stimulus metadata
                row.humanStimulusID = choice.stimulusID;
                row.humanPosition = choice.position;
                row.humanReward = choice.reward;
                row.humanCategory = choice.category;
                row.humanContrast = choice.contrast;
                row.humanOrientation = choice.orientation;
                row.humanCurvature = choice.curvature;
                row.humanSharpness = choice.sharpness;

                % Preceding agent choice (if available)
                prevAgent = state.previousAgentChoice;
                if prevAgent.exists
                    row.agentStimulusID = prevAgent.stimulusID;
                    row.agentPosition = prevAgent.position;
                    row.agentReward = prevAgent.reward;
                    row.agentCategory = prevAgent.category;
                    row.agentContrast = prevAgent.contrast;
                    row.agentOrientation = prevAgent.orientation;
                    row.agentCurvature = prevAgent.curvature;
                    row.agentSharpness = prevAgent.sharpness;

                    row.agentRuleSatisfied = prevAgent.ruleSatisfied;
                    row.agentRepeatedOwnLocation = prevAgent.repeatedOwn;
                    row.agentRepeatedHumanLocation = prevAgent.repeatedOther;
                    row.agentNoRewardRuleViolation = prevAgent.noRewardRuleViolation;
                    row.agentNoRewardRepeatedOwnLocation = prevAgent.noRewardRepeatedOwn;
                    row.agentNoRewardRepeatedHumanLocation = prevAgent.noRewardRepeatedOther;

                    row.agentDistanceFromPreviousHuman = prevAgent.distanceFromPreviousOther;
                    row.agentHumanDistance = computeManhattanDistance(prevAgent.position, choice.position, boardColumnCount);
                    row.humanDistanceFromPreviousAgent = row.agentHumanDistance;
                end

                % Current human rule/repeat/no-reward explanation
                row.humanRuleSatisfied = choice.ruleSatisfied;
                row.humanRepeatedOwnLocation = choice.repeatedOwn;
                row.humanRepeatedAgentLocation = choice.repeatedOther;

                row.humanNoRewardRuleViolation = (~choice.reward) && (~choice.ruleSatisfied);
                row.humanNoRewardRepeatedOwnLocation = (~choice.reward) && choice.repeatedOwn;
                row.humanNoRewardRepeatedAgentLocation = (~choice.reward) && choice.repeatedOther;

                % Defer score fill until score_update for this move.
                state.pendingHumanRow = row;
                state.hasPendingHumanRow = true;

                state.previousHumanChoice = choice;
                state.lastMove = eventData;

                if ~choice.repeat
                    state.selectedByHuman = addUnique(state.selectedByHuman, choice.position);
                end
                state.lastStimulusSelection = struct();
                state.lastRepeatedSelection = struct();

            otherwise
                % Ignore unexpected events unless needed for reconstruction.
        end
    end

    if state.hasPendingHumanRow
        rows(end + 1, 1) = finalizePendingHumanRow(state.pendingHumanRow, state); %#ok<AGROW>
        state.hasPendingHumanRow = false;
    end

    validateRequiredCoverage(state);

    if isempty(rows)
        trials = emptyTrialsTable();
        validateHumanMoveRowCount(trials, events);
        validateFinalScoreUpdateAlignment(trials, events);
        return;
    end

    trials = struct2table(rows);
    validateHumanMoveRowCount(trials, events);
    validateFinalScoreUpdateAlignment(trials, events);
end

function validateInputs(session, stimuli, rules)
    if nargin < 3
        error('buildTrialTable:MissingInput', 'session, stimuli, and rules are required.');
    end

    if ~isstruct(session)
        error('buildTrialTable:InvalidSessionInput', 'session must be a struct returned by loadSession().');
    end
    if ~istable(stimuli)
        error('buildTrialTable:InvalidStimuliInput', 'stimuli must be a table returned by buildStimulusTable().');
    end
    if ~istable(rules)
        error('buildTrialTable:InvalidRulesInput', 'rules must be a table returned by buildRuleTable().');
    end

    requiredStimulusVars = {'stimulusID','category','contrast','orientation','curvature','sharpness'};
    requiredRuleVars = {'ruleName','ruleType','feature','operator','value','minimumDistance'};

    assertTableVariables(stimuli, requiredStimulusVars, 'buildTrialTable:StimulusTableMissingVariables');
    assertTableVariables(rules, requiredRuleVars, 'buildTrialTable:RuleTableMissingVariables');
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end

function state = initialState()
    state.currentRule = "";
    state.currentEpisode = NaN;
    state.currentPhase = "";
    state.currentBlock = NaN;

    state.humanEpisodeScore = 0;
    state.agentEpisodeScore = 0;
    state.humanTotalScore = 0;
    state.agentTotalScore = 0;

    state.previousAgentChoice = emptyChoice();
    state.previousHumanChoice = emptyChoice();

    state.selectedByHuman = zeros(0, 1);
    state.selectedByAgent = zeros(0, 1);

    state.trialWithinEpisode = 0;
    state.humanSelectionNumber = 0;

    state.pendingHumanRow = defaultTrialRow();
    state.hasPendingHumanRow = false;

    state.rewardsRemaining = NaN;

    state.lastStimulusSelection = struct();
    state.lastRepeatedSelection = struct();
    state.lastMove = struct();

    state.seenEpisodeStart = false;
    state.seenHumanMove = false;
    state.seenAgentMove = false;
end

function validateRequiredCoverage(state)
    if ~state.seenEpisodeStart
        error('buildTrialTable:MissingEpisodeStart', ...
            'Session eventLog is missing required event type "episode_start".');
    end
    if ~state.seenHumanMove
        error('buildTrialTable:MissingHumanMove', ...
            'Session eventLog is missing required event type "human_move".');
    end
    if ~state.seenAgentMove
        error('buildTrialTable:MissingAgentMove', ...
            'Session eventLog is missing required event type "agent_move".');
    end
end

function idx = buildNumericIndex(tbl, varName)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'double');
    values = tbl.(varName);
    for i = 1:height(tbl)
        key = numericKey(values(i));
        idx(key) = i;
    end
end

function idx = buildStringIndex(tbl, varName)
    idx = containers.Map('KeyType', 'char', 'ValueType', 'double');
    values = string(tbl.(varName));
    for i = 1:height(tbl)
        idx(char(values(i))) = i;
    end
end

function key = numericKey(v)
    key = sprintf('%.15g', double(v));
end

function choice = parseMoveChoice(eventData, actor, state, stimIndex, stimuli, ruleIndex, rules, boardColumnCount)
    actor = char(actor);

    choice = emptyChoice();
    choice.exists = true;
    choice.episode = asNumber(afField(eventData, 'episodeNumber', state.currentEpisode), state.currentEpisode);
    choice.position = asNumber(afField(eventData, 'positionID', NaN), NaN);
    choice.stimulusID = asNumber(afField(eventData, 'stimulusID', NaN), NaN);
    choice.reward = asLogical(afField(eventData, 'reward', false), false);
    choice.repeat = asLogical(afField(eventData, 'repeat', false), false);

    if isnan(choice.position)
        error('buildTrialTable:MissingPositionID', 'Move event is missing required data.positionID.');
    end
    if isnan(choice.stimulusID)
        error('buildTrialTable:MissingStimulusID', 'Move event is missing required data.stimulusID.');
    end

    stim = getStimulusRow(choice.stimulusID, stimIndex, stimuli);
    choice.category = stim.category;
    choice.contrast = stim.contrast;
    choice.orientation = stim.orientation;
    choice.curvature = stim.curvature;
    choice.sharpness = stim.sharpness;

    activeRule = getActiveRuleRow(state.currentRule, ruleIndex, rules);

    if strcmp(actor, 'human')
        repeatedOwn = any(state.selectedByHuman == choice.position);
        repeatedOther = any(state.selectedByAgent == choice.position);
        previousOtherChoice = state.previousAgentChoice;
    else
        repeatedOwn = any(state.selectedByAgent == choice.position);
        repeatedOther = any(state.selectedByHuman == choice.position);
        previousOtherChoice = state.previousHumanChoice;
    end

    choice.repeatedOwn = repeatedOwn;
    choice.repeatedOther = repeatedOther;

    previousOtherPosition = NaN;
    if previousOtherChoice.exists
        previousOtherPosition = previousOtherChoice.position;
    end

    choice.ruleSatisfied = evaluateRuleSatisfied(activeRule, stim, choice.position, previousOtherPosition, boardColumnCount);

    choice.noRewardRuleViolation = (~choice.reward) && (~choice.ruleSatisfied);
    choice.noRewardRepeatedOwn = (~choice.reward) && choice.repeatedOwn;
    choice.noRewardRepeatedOther = (~choice.reward) && choice.repeatedOther;

    if ~isnan(previousOtherPosition)
        choice.distanceFromPreviousOther = computeManhattanDistance(choice.position, previousOtherPosition, boardColumnCount);
    else
        choice.distanceFromPreviousOther = NaN;
    end
end

function row = getStimulusRow(stimulusID, stimIndex, stimuli)
    key = numericKey(stimulusID);
    if ~isKey(stimIndex, key)
        error('buildTrialTable:UnknownStimulusID', ...
            'Stimulus ID %g was observed in eventLog but is missing from stimuli table.', stimulusID);
    end
    row = stimuli(stimIndex(key), :);
end

function rule = getActiveRuleRow(ruleName, ruleIndex, rules)
    rn = asString(ruleName);
    if strlength(rn) == 0
        error('buildTrialTable:MissingActiveRule', ...
            'Could not determine active rule for one or more move events (missing episode_start/rule_change rule file).');
    end
    key = char(rn);
    if ~isKey(ruleIndex, key)
        error('buildTrialTable:UnknownRule', ...
            'Active rule "%s" is not present in rules table.', key);
    end
    rule = rules(ruleIndex(key), :);
end

function satisfied = evaluateRuleSatisfied(ruleRow, stimulusRow, positionID, previousReferencePositionID, boardColumnCount)
    ruleType = asString(ruleRow.ruleType);

    switch ruleType
        case "feature"
            featureName = asString(ruleRow.feature);
            operator = asString(ruleRow.operator);
            targetValue = ruleRow.value;

            if strlength(featureName) == 0
                error('buildTrialTable:InvalidRuleRow', 'Feature rule is missing feature name.');
            end

            if ~ismember(char(featureName), stimulusRow.Properties.VariableNames)
                error('buildTrialTable:UnsupportedFeature', ...
                    'Rule feature "%s" is not present in the stimulus table.', char(featureName));
            end

            actualValue = stimulusRow.(char(featureName));
            actualValue = double(actualValue(1));
            targetValue = double(targetValue(1));

            satisfied = evaluateOperator(actualValue, operator, targetValue);

        case "distance-from-agent"
            if isnan(previousReferencePositionID)
                satisfied = false;
                return;
            end

            minimumDistance = ruleRow.minimumDistance;
            minimumDistance = double(minimumDistance(1));
            distance = computeManhattanDistance(positionID, previousReferencePositionID, boardColumnCount);
            satisfied = distance >= minimumDistance;

        otherwise
            error('buildTrialTable:UnsupportedRuleType', ...
                'Unsupported rule type "%s" in rules table.', char(ruleType));
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
            error('buildTrialTable:UnsupportedOperator', ...
                'Unsupported rule operator "%s".', char(operator));
    end
end

function d = computeManhattanDistance(positionA, positionB, boardColumnCount)
    if isnan(boardColumnCount)
        error('buildTrialTable:MissingBoardGeometry', ...
            ['Cannot compute Manhattan distance because board column count ', ...
             'could not be reconstructed from session metadata.']);
    end

    cols = floor(boardColumnCount);
    if cols <= 0
        error('buildTrialTable:InvalidBoardGeometry', ...
            'Board column count must be positive. Found: %g', boardColumnCount);
    end

    % NOTE: This assumes position IDs are zero-based grid indices.
    rowA = floor(positionA / cols);
    colA = mod(positionA, cols);
    rowB = floor(positionB / cols);
    colB = mod(positionB, cols);

    d = abs(rowA - rowB) + abs(colA - colB);
end

function validateOptionalMoveConsistency(moveData, expectedActor, state)
    if ~isempty(fieldnames(state.lastStimulusSelection))
        selActor = asString(afField(state.lastStimulusSelection, 'actor', ""));
        selPosition = asNumber(afField(state.lastStimulusSelection, 'positionID', NaN), NaN);
        selStimulus = asNumber(afField(state.lastStimulusSelection, 'stimulusID', NaN), NaN);

        moveActor = asString(afField(moveData, 'actor', expectedActor));
        movePosition = asNumber(afField(moveData, 'positionID', NaN), NaN);
        moveStimulus = asNumber(afField(moveData, 'stimulusID', NaN), NaN);

        if strlength(selActor) > 0 && strlength(moveActor) > 0 && selActor ~= moveActor
            warning('buildTrialTable:StimulusSelectionMismatch', ...
                'stimulus_selection actor (%s) does not match %s_move actor (%s).', ...
                char(selActor), expectedActor, char(moveActor));
        end
        if ~isnan(selPosition) && ~isnan(movePosition) && selPosition ~= movePosition
            warning('buildTrialTable:StimulusSelectionMismatch', ...
                'stimulus_selection positionID (%g) does not match %s_move positionID (%g).', ...
                selPosition, expectedActor, movePosition);
        end
        if ~isnan(selStimulus) && ~isnan(moveStimulus) && selStimulus ~= moveStimulus
            warning('buildTrialTable:StimulusSelectionMismatch', ...
                'stimulus_selection stimulusID (%g) does not match %s_move stimulusID (%g).', ...
                selStimulus, expectedActor, moveStimulus);
        end
    end

    if ~isempty(fieldnames(state.lastRepeatedSelection))
        moveRepeat = asLogical(afField(moveData, 'repeat', false), false);
        repActor = asString(afField(state.lastRepeatedSelection, 'actor', ""));
        if ~moveRepeat
            warning('buildTrialTable:RepeatedSelectionMismatch', ...
                'repeated_stimulus_selection observed before %s_move with repeat=false.', expectedActor);
        end
        if strlength(repActor) > 0 && repActor ~= asString(expectedActor)
            warning('buildTrialTable:RepeatedSelectionMismatch', ...
                'repeated_stimulus_selection actor (%s) does not match %s_move actor.', ...
                char(repActor), expectedActor);
        end
    end
end

function state = validateOptionalRewardDelivered(state, rewardData)
    if isempty(fieldnames(state.lastMove))
        return;
    end

    moveReward = asLogical(afField(state.lastMove, 'reward', false), false);
    rewardActor = asString(afField(rewardData, 'actor', ""));
    moveActor = asString(afField(state.lastMove, 'actor', ""));

    if ~moveReward
        warning('buildTrialTable:UnexpectedRewardDelivered', ...
            'reward_delivered observed after move with reward=false.');
    end

    if strlength(rewardActor) > 0 && strlength(moveActor) > 0 && rewardActor ~= moveActor
        warning('buildTrialTable:RewardActorMismatch', ...
            'reward_delivered actor (%s) does not match previous move actor (%s).', ...
            char(rewardActor), char(moveActor));
    end

    rewardMove = asNumber(afField(rewardData, 'moveNumber', NaN), NaN);
    moveMove = asNumber(afField(state.lastMove, 'moveNumber', NaN), NaN);
    if ~isnan(rewardMove) && ~isnan(moveMove) && rewardMove ~= moveMove
        warning('buildTrialTable:RewardMoveMismatch', ...
            'reward_delivered moveNumber (%g) does not match previous moveNumber (%g).', ...
            rewardMove, moveMove);
    end

    rewardEpisode = asNumber(afField(rewardData, 'episodeNumber', NaN), NaN);
    moveEpisode = asNumber(afField(state.lastMove, 'episodeNumber', NaN), NaN);
    if ~isnan(rewardEpisode) && ~isnan(moveEpisode) && rewardEpisode ~= moveEpisode
        warning('buildTrialTable:RewardEpisodeMismatch', ...
            'reward_delivered episodeNumber (%g) does not match previous move episodeNumber (%g).', ...
            rewardEpisode, moveEpisode);
    end
end

function row = finalizePendingHumanRow(row, state)
    row.humanEpisodeScore = state.humanEpisodeScore;
    row.agentEpisodeScore = state.agentEpisodeScore;
    row.humanTotalScore = state.humanTotalScore;
    row.agentTotalScore = state.agentTotalScore;
    row.rewardsRemaining = state.rewardsRemaining;
end

function v = addUnique(v, value)
    if ~any(v == value)
        v(end + 1, 1) = value; %#ok<AGROW>
    end
end

function choice = emptyChoice()
    choice = struct( ...
        'exists', false, ...
        'episode', NaN, ...
        'stimulusID', NaN, ...
        'position', NaN, ...
        'reward', false, ...
        'repeat', false, ...
        'category', NaN, ...
        'contrast', NaN, ...
        'orientation', NaN, ...
        'curvature', NaN, ...
        'sharpness', NaN, ...
        'ruleSatisfied', false, ...
        'repeatedOwn', false, ...
        'repeatedOther', false, ...
        'distanceFromPreviousOther', NaN, ...
        'noRewardRuleViolation', false, ...
        'noRewardRepeatedOwn', false, ...
        'noRewardRepeatedOther', false ...
    );
end

function row = defaultTrialRow()
    row = struct( ...
        'block', NaN, ...
        'phase', string(missing), ...
        'episode', NaN, ...
        'trialWithinEpisode', NaN, ...
        'humanSelectionNumber', NaN, ...
        'ruleName', string(missing), ...
        'ruleType', string(missing), ...
        'feature', string(missing), ...
        'operator', string(missing), ...
        'value', NaN, ...
        'minimumDistance', NaN, ...
        'humanStimulusID', NaN, ...
        'humanPosition', NaN, ...
        'humanReward', false, ...
        'humanCategory', NaN, ...
        'humanContrast', NaN, ...
        'humanOrientation', NaN, ...
        'humanCurvature', NaN, ...
        'humanSharpness', NaN, ...
        'agentStimulusID', NaN, ...
        'agentPosition', NaN, ...
        'agentReward', false, ...
        'agentCategory', NaN, ...
        'agentContrast', NaN, ...
        'agentOrientation', NaN, ...
        'agentCurvature', NaN, ...
        'agentSharpness', NaN, ...
        'agentHumanDistance', NaN, ...
        'humanDistanceFromPreviousAgent', NaN, ...
        'agentDistanceFromPreviousHuman', NaN, ...
        'humanRuleSatisfied', false, ...
        'agentRuleSatisfied', false, ...
        'humanRepeatedOwnLocation', false, ...
        'humanRepeatedAgentLocation', false, ...
        'agentRepeatedOwnLocation', false, ...
        'agentRepeatedHumanLocation', false, ...
        'humanNoRewardRuleViolation', false, ...
        'humanNoRewardRepeatedOwnLocation', false, ...
        'humanNoRewardRepeatedAgentLocation', false, ...
        'agentNoRewardRuleViolation', false, ...
        'agentNoRewardRepeatedOwnLocation', false, ...
        'agentNoRewardRepeatedHumanLocation', false, ...
        'humanEpisodeScore', NaN, ...
        'agentEpisodeScore', NaN, ...
        'humanTotalScore', NaN, ...
        'agentTotalScore', NaN, ...
        'rewardsRemaining', NaN ...
    );
end

function tbl = emptyTrialsTable()
    tbl = struct2table(repmat(defaultTrialRow(), 0, 1));
end

function value = asString(raw)
    if isstring(raw)
        if isempty(raw)
            value = "";
        else
            value = string(raw(1));
        end
        return;
    end
    if ischar(raw)
        value = string(raw);
        return;
    end
    if isempty(raw)
        value = "";
        return;
    end
    value = string(raw);
end

function value = asNumber(raw, defaultValue)
    if nargin < 2
        defaultValue = NaN;
    end

    if isnumeric(raw) || islogical(raw)
        if isempty(raw)
            value = defaultValue;
        else
            value = double(raw(1));
        end
        return;
    end

    if isstring(raw) || ischar(raw)
        numericValue = str2double(string(raw));
        if isnan(numericValue)
            value = defaultValue;
        else
            value = numericValue;
        end
        return;
    end

    value = defaultValue;
end

function value = asLogical(raw, defaultValue)
    if nargin < 2
        defaultValue = false;
    end

    if islogical(raw)
        if isempty(raw)
            value = defaultValue;
        else
            value = logical(raw(1));
        end
        return;
    end

    if isnumeric(raw)
        if isempty(raw) || isnan(raw(1))
            value = defaultValue;
        else
            value = logical(raw(1) ~= 0);
        end
        return;
    end

    if isstring(raw) || ischar(raw)
        s = lower(strtrim(char(string(raw))));
        if any(strcmp(s, {'true','1','yes'}))
            value = true;
            return;
        end
        if any(strcmp(s, {'false','0','no'}))
            value = false;
            return;
        end
    end

    value = defaultValue;
end

function validateHumanMoveRowCount(trials, events)
    humanMoveCount = 0;
    for i = 1:numel(events)
        if string(afField(events(i), 'type', "")) == "human_move"
            humanMoveCount = humanMoveCount + 1;
        end
    end

    rowCount = height(trials);
    if rowCount ~= humanMoveCount
        error('buildTrialTable:HumanMoveRowMismatch', ...
            ['Row count mismatch: found %d human_move events in session.eventLog ', ...
             'but produced %d trial rows.'], ...
            humanMoveCount, rowCount);
    end
end

function validateFinalScoreUpdateAlignment(trials, events)
    if isempty(trials)
        return;
    end

    finalScoreData = struct();
    foundScoreUpdate = false;
    for i = 1:numel(events)
        if string(afField(events(i), 'type', "")) == "score_update"
            finalScoreData = afField(events(i), 'data', struct());
            if ~isstruct(finalScoreData)
                finalScoreData = struct();
            end
            foundScoreUpdate = true;
        end
    end

    if ~foundScoreUpdate
        error('buildTrialTable:MissingScoreUpdate', ...
            'Could not validate final trial row because no score_update event was found.');
    end

    lastRow = trials(end, :);
    compareFinalField('humanEpisodeScore', lastRow.humanEpisodeScore, asNumber(afField(finalScoreData, 'humanScore', NaN), NaN));
    compareFinalField('agentEpisodeScore', lastRow.agentEpisodeScore, asNumber(afField(finalScoreData, 'agentScore', NaN), NaN));
    compareFinalField('humanTotalScore', lastRow.humanTotalScore, asNumber(afField(finalScoreData, 'humanTotalScore', NaN), NaN));
    compareFinalField('agentTotalScore', lastRow.agentTotalScore, asNumber(afField(finalScoreData, 'agentTotalScore', NaN), NaN));
    compareFinalField('rewardsRemaining', lastRow.rewardsRemaining, asNumber(afField(finalScoreData, 'rewardsRemaining', NaN), NaN));
end

function compareFinalField(fieldName, parserValue, eventValue)
    parserValue = asNumber(parserValue, NaN);
    eventValue = asNumber(eventValue, NaN);
    if ~isequaln(parserValue, eventValue)
        error('buildTrialTable:FinalScoreMismatch', ...
            'Final %s mismatch: parser=%g, eventLog=%g.', fieldName, parserValue, eventValue);
    end
end
