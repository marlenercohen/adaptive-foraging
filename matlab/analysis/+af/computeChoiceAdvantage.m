function choiceAdvantage = computeChoiceAdvantage(decisionState, ruleConsistency)
%af.computeChoiceAdvantage Opportunity-corrected active-rule choice metric.
%   CHOICEADVANTAGE = af.computeChoiceAdvantage(DECISIONSTATE,
%   RULECONSISTENCY) returns one row per human decision with an objective
%   opportunity-corrected measure of active-rule selection.
%
%   This function is intentionally model-agnostic. It does not infer
%   beliefs, fit models, or estimate hidden states.
%
%   Required availability information must already exist in decisionState.
%   This function does not reconstruct board availability from scratch.

    if nargin < 2
        error('af:computeChoiceAdvantage:MissingInput', ...
            'decisionState and ruleConsistency are required.');
    end
    if ~istable(decisionState)
        error('af:computeChoiceAdvantage:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end
    if ~istable(ruleConsistency)
        error('af:computeChoiceAdvantage:InvalidRuleConsistencyType', ...
            'ruleConsistency must be a table from af.evaluateRuleConsistency().');
    end

    requiredDecisionVars = {
        'decisionID', ...
        'globalDecisionIndex', ...
        'episode', ...
        'ruleName', ...
        'humanDecisionIndexEpisode'
    };
    assertTableVariables(decisionState, requiredDecisionVars, ...
        'af:computeChoiceAdvantage:MissingDecisionStateVariables');

    requiredConsistencyVars = {
        'decisionID', ...
        'candidateRuleName', ...
        'isCandidateActiveRule', ...
        'ruleSatisfied'
    };
    assertTableVariables(ruleConsistency, requiredConsistencyVars, ...
        'af:computeChoiceAdvantage:MissingRuleConsistencyVariables');

    % This function requires active-rule opportunity counts to already be
    % present in Layer 2. Without them, availability would need to be
    % reconstructed from board state, which is explicitly out of scope.
    requiredAvailabilityVars = {
        'numberAvailableStimuliBeforeDecision', ...
        'numberAvailableMatchingActiveRuleBeforeDecision'
    };
    missingAvailabilityVars = requiredAvailabilityVars( ...
        ~ismember(requiredAvailabilityVars, decisionState.Properties.VariableNames));
    if ~isempty(missingAvailabilityVars)
        error('af:computeChoiceAdvantage:MissingAvailabilityState', ...
            ['decisionState is missing required Layer-2 availability field(s): %s. ', ...
             'computeChoiceAdvantage needs the number of available stimuli and ', ...
             'the number of available stimuli satisfying the objectively active ', ...
             'rule immediately before each human decision. Add these fields to ', ...
             'Layer 2 rather than reconstructing availability inside this function.'], ...
            strjoin(missingAvailabilityVars, ', '));
    end

    if isempty(decisionState)
        choiceAdvantage = table();
        return;
    end

    ds = decisionState;
    [~, order] = sort(double(ds.globalDecisionIndex));
    ds = ds(order, :);

    rc = ruleConsistency(logical(ruleConsistency.isCandidateActiveRule), :);
    if isempty(rc)
        error('af:computeChoiceAdvantage:NoActiveRuleRows', ...
            'ruleConsistency does not contain any rows with isCandidateActiveRule=true.');
    end

    activeCounts = groupsummary(table(double(rc.decisionID), 'VariableNames', {'decisionID'}), 'decisionID');
    badCounts = activeCounts.GroupCount ~= 1;
    if any(badCounts)
        badId = activeCounts.decisionID(find(badCounts, 1, 'first'));
        error('af:computeChoiceAdvantage:ActiveRuleRowMismatch', ...
            'Expected exactly one active-rule row in ruleConsistency for decisionID %g.', badId);
    end

    rcActive = rc(:, {'decisionID', 'candidateRuleName', 'ruleSatisfied'});
    rcActive.Properties.VariableNames = {'decisionID', 'activeRuleNameFromConsistency', 'observedChoice'};
    rcActive.observedChoice = logical(rcActive.observedChoice);

    choiceAdvantage = join(ds, rcActive, 'Keys', 'decisionID');
    if height(choiceAdvantage) ~= height(ds)
        error('af:computeChoiceAdvantage:JoinMismatch', ...
            ['Could not align one active-rule consistency row to every decision. ', ...
             'Check decisionID coverage in ruleConsistency.']);
    end

    choiceAdvantage.ruleName = string(choiceAdvantage.ruleName);
    choiceAdvantage.activeRuleNameFromConsistency = string(choiceAdvantage.activeRuleNameFromConsistency);
    if any(choiceAdvantage.ruleName ~= choiceAdvantage.activeRuleNameFromConsistency)
        idx = find(choiceAdvantage.ruleName ~= choiceAdvantage.activeRuleNameFromConsistency, 1, 'first');
        error('af:computeChoiceAdvantage:ActiveRuleNameMismatch', ...
            ['decisionState.ruleName (%s) does not match active rule from ', ...
             'ruleConsistency (%s) for decisionID %g.'], ...
            choiceAdvantage.ruleName(idx), ...
            choiceAdvantage.activeRuleNameFromConsistency(idx), ...
            choiceAdvantage.decisionID(idx));
    end

    numberAvailableStimuli = double(choiceAdvantage.numberAvailableStimuliBeforeDecision);
    numberAvailableMatching = double(choiceAdvantage.numberAvailableMatchingActiveRuleBeforeDecision);

    if any(numberAvailableStimuli <= 0 | isnan(numberAvailableStimuli))
        idx = find(numberAvailableStimuli <= 0 | isnan(numberAvailableStimuli), 1, 'first');
        error('af:computeChoiceAdvantage:InvalidAvailableStimulusCount', ...
            'numberAvailableStimuliBeforeDecision must be positive for decisionID %g.', ...
            choiceAdvantage.decisionID(idx));
    end

    if any(numberAvailableMatching < 0 | isnan(numberAvailableMatching))
        idx = find(numberAvailableMatching < 0 | isnan(numberAvailableMatching), 1, 'first');
        error('af:computeChoiceAdvantage:InvalidMatchingStimulusCount', ...
            'numberAvailableMatchingActiveRuleBeforeDecision must be nonnegative for decisionID %g.', ...
            choiceAdvantage.decisionID(idx));
    end

    if any(numberAvailableMatching > numberAvailableStimuli)
        idx = find(numberAvailableMatching > numberAvailableStimuli, 1, 'first');
        error('af:computeChoiceAdvantage:MatchingCountExceedsAvailable', ...
            ['numberAvailableMatchingActiveRuleBeforeDecision exceeds ', ...
             'numberAvailableStimuliBeforeDecision for decisionID %g.'], ...
            choiceAdvantage.decisionID(idx));
    end

    availableFraction = numberAvailableMatching ./ numberAvailableStimuli;
    observedChoice = double(logical(choiceAdvantage.observedChoice));
    advantage = observedChoice - availableFraction;

    % Episode number within the current rule run.
    ruleEpisodeNumber = nan(height(choiceAdvantage), 1);
    currentRule = "";
    currentCount = 0;
    currentEpisode = NaN;
    for i = 1:height(choiceAdvantage)
        thisRule = choiceAdvantage.ruleName(i);
        thisEpisode = double(choiceAdvantage.episode(i));
        if i == 1 || thisRule ~= currentRule
            currentRule = thisRule;
            currentCount = 1;
            currentEpisode = thisEpisode;
        elseif thisEpisode ~= currentEpisode
            currentCount = currentCount + 1;
            currentEpisode = thisEpisode;
        end
        ruleEpisodeNumber(i) = currentCount;
    end

    % Keep a compact output schema focused on the requested quantity.
    keepVars = {'decisionID', 'globalDecisionIndex', 'episode', 'ruleName', 'humanDecisionIndexEpisode'};
    keepVars = keepVars(ismember(keepVars, choiceAdvantage.Properties.VariableNames));
    if ismember('sessionID', choiceAdvantage.Properties.VariableNames)
        keepVars = [{'sessionID'}, keepVars];
    end
    if ismember('participantID', choiceAdvantage.Properties.VariableNames)
        keepVars = [{'participantID'}, keepVars];
    end

    choiceAdvantage = choiceAdvantage(:, keepVars);
    choiceAdvantage.ruleEpisodeNumber = ruleEpisodeNumber;
    choiceAdvantage.observedChoice = logical(observedChoice);
    choiceAdvantage.availableFraction = availableFraction;
    choiceAdvantage.choiceAdvantage = advantage;
    choiceAdvantage.numberAvailableStimuli = numberAvailableStimuli;
    choiceAdvantage.numberAvailableMatchingStimuli = numberAvailableMatching;

    validateChoiceAdvantage(choiceAdvantage);
end

function validateChoiceAdvantage(tbl)
    if any(tbl.availableFraction < 0 | tbl.availableFraction > 1 | isnan(tbl.availableFraction))
        idx = find(tbl.availableFraction < 0 | tbl.availableFraction > 1 | isnan(tbl.availableFraction), 1, 'first');
        error('af:computeChoiceAdvantage:InvalidAvailableFraction', ...
            'availableFraction must lie in [0, 1] for decisionID %g.', tbl.decisionID(idx));
    end

    if any(tbl.choiceAdvantage < -1 | tbl.choiceAdvantage > 1 | isnan(tbl.choiceAdvantage))
        idx = find(tbl.choiceAdvantage < -1 | tbl.choiceAdvantage > 1 | isnan(tbl.choiceAdvantage), 1, 'first');
        error('af:computeChoiceAdvantage:InvalidChoiceAdvantage', ...
            'choiceAdvantage must lie in [-1, 1] for decisionID %g.', tbl.decisionID(idx));
    end

    zeroMask = tbl.numberAvailableMatchingStimuli == 0;
    if any(tbl.availableFraction(zeroMask) ~= 0)
        idx = find(zeroMask & tbl.availableFraction ~= 0, 1, 'first');
        error('af:computeChoiceAdvantage:ZeroMatchingFractionMismatch', ...
            ['availableFraction must equal 0 when ', ...
             'numberAvailableMatchingStimuli == 0 (decisionID %g).'], ...
            tbl.decisionID(idx));
    end

    allMask = tbl.numberAvailableMatchingStimuli == tbl.numberAvailableStimuli;
    if any(tbl.availableFraction(allMask) ~= 1)
        idx = find(allMask & tbl.availableFraction ~= 1, 1, 'first');
        error('af:computeChoiceAdvantage:AllMatchingFractionMismatch', ...
            ['availableFraction must equal 1 when all available stimuli ', ...
             'match the rule (decisionID %g).'], ...
            tbl.decisionID(idx));
    end
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
