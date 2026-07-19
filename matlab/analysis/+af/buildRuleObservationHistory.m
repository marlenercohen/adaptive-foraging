function history = buildRuleObservationHistory(decisionState, ruleConsistency)
%af.buildRuleObservationHistory Objective pre-decision rule observation history.
%   HISTORY = af.buildRuleObservationHistory(DECISIONSTATE, RULECONSISTENCY)
%   returns one row per (human decision x candidate rule) with cumulative
%   objective observation counts available before that decision.
%
%   This function is intentionally model-agnostic. It does not estimate
%   probabilities, evidence, beliefs, confidence, or latent values.
%
%   Notes on scope:
%   - Consistency-vs-candidate counts are computed from observations for
%     which candidate-rule evaluation is available in RULECONSISTENCY.
%   - With the current pipeline, those evaluated observations are human
%     decisions (not preceding agent decisions).

    if nargin < 2
        error('af:buildRuleObservationHistory:MissingInput', ...
            'decisionState and ruleConsistency are required.');
    end
    if ~istable(decisionState)
        error('af:buildRuleObservationHistory:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end
    if ~istable(ruleConsistency)
        error('af:buildRuleObservationHistory:InvalidRuleConsistencyType', ...
            'ruleConsistency must be a table from af.evaluateRuleConsistency().');
    end

    requiredDecisionVars = {
        'decisionID', ...
        'globalDecisionIndex', ...
        'episode', ...
        'currentHumanReward', ...
        'previousAgentReward', ...
        'previousAgentStimulusID'
    };
    assertTableVariables(decisionState, requiredDecisionVars, ...
        'af:buildRuleObservationHistory:MissingDecisionStateVariables');

    requiredConsistencyVars = {
        'decisionID', ...
        'globalDecisionIndex', ...
        'candidateRuleName', ...
        'candidateRuleType', ...
        'candidateFeature', ...
        'candidateOperator', ...
        'candidateValue', ...
        'candidateMinimumDistance', ...
        'ruleSatisfied', ...
        'hasRequiredContext'
    };
    assertTableVariables(ruleConsistency, requiredConsistencyVars, ...
        'af:buildRuleObservationHistory:MissingRuleConsistencyVariables');

    if isempty(decisionState) || isempty(ruleConsistency)
        history = table();
        return;
    end

    ds = decisionState;
    [~, dOrd] = sort(double(ds.globalDecisionIndex));
    ds = ds(dOrd, :);

    rc = ruleConsistency;
    [~, cOrd] = sortrows([double(rc.globalDecisionIndex), double(categorical(string(rc.candidateRuleName)))]);
    rc = rc(cOrd, :);

    % Objective observation stream components.
    humanObserved = true(height(ds), 1);
    humanRewarded = logical(ds.currentHumanReward);

    agentObserved = ~isnan(double(ds.previousAgentStimulusID));
    agentRewarded = false(height(ds), 1);
    agentRewarded(agentObserved) = logical(ds.previousAgentReward(agentObserved));

    nDecisions = height(ds);

    candidateKeys = unique(string(rc.candidateRuleName), 'stable');
    nRules = numel(candidateKeys);

    nOut = height(rc);
    history = table();
    history.decisionID = rc.decisionID;
    history.globalDecisionIndex = rc.globalDecisionIndex;
    history.candidateRuleName = string(rc.candidateRuleName);
    history.candidateRuleType = string(rc.candidateRuleType);
    history.candidateFeature = string(rc.candidateFeature);
    history.candidateOperator = string(rc.candidateOperator);
    history.candidateValue = rc.candidateValue;
    history.candidateMinimumDistance = rc.candidateMinimumDistance;

    history.currentObservationEvaluated = false(nOut, 1);
    history.currentObservationConsistent = false(nOut, 1);

    history.nRelevantObservationsBeforeDecision = zeros(nOut, 1);
    history.nConsistentObservationsBeforeDecision = zeros(nOut, 1);
    history.nInconsistentObservationsBeforeDecision = zeros(nOut, 1);
    history.cumulativeConsistencyBeforeDecision = nan(nOut, 1);

    history.nHumanObservationsBeforeDecision = zeros(nOut, 1);
    history.nAgentObservationsBeforeDecision = zeros(nOut, 1);
    history.nRewardedObservationsBeforeDecision = zeros(nOut, 1);
    history.nUnrewardedObservationsBeforeDecision = zeros(nOut, 1);

    history.agentConsistencyIncludedInCandidateCounts = false(nOut, 1);

    % Build index from decisionID to decision row position in sorted stream.
    decisionIds = double(ds.decisionID);
    posByDecisionId = containers.Map('KeyType', 'double', 'ValueType', 'double');
    for i = 1:nDecisions
        posByDecisionId(decisionIds(i)) = i;
    end

    % Objective cumulative observation counts before each decision.
    nHumanBefore = zeros(nDecisions, 1);
    nAgentBefore = zeros(nDecisions, 1);
    nRewardedBefore = zeros(nDecisions, 1);
    nUnrewardedBefore = zeros(nDecisions, 1);

    cHum = 0;
    cAg = 0;
    cRew = 0;
    cUnr = 0;

    for i = 1:nDecisions
        % Agent observation that occurred immediately before this decision.
        if agentObserved(i)
            cAg = cAg + 1;
            if agentRewarded(i)
                cRew = cRew + 1;
            else
                cUnr = cUnr + 1;
            end
        end

        nHumanBefore(i) = cHum;
        nAgentBefore(i) = cAg;
        nRewardedBefore(i) = cRew;
        nUnrewardedBefore(i) = cUnr;

        % Current human observation becomes available after this decision.
        if humanObserved(i)
            cHum = cHum + 1;
            if humanRewarded(i)
                cRew = cRew + 1;
            else
                cUnr = cUnr + 1;
            end
        end
    end

    for r = 1:nRules
        ruleKey = candidateKeys(r);
        rMask = string(rc.candidateRuleName) == ruleKey;
        rRows = find(rMask);

        if isempty(rRows)
            continue;
        end

        % For each decision, candidate evaluation of that decision's human
        % outcome is available via ruleConsistency.
        relByDecision = false(nDecisions, 1);
        consByDecision = false(nDecisions, 1);

        for k = 1:numel(rRows)
            rr = rRows(k);
            did = double(rc.decisionID(rr));
            if ~isKey(posByDecisionId, did)
                error('af:buildRuleObservationHistory:DecisionMismatch', ...
                    'ruleConsistency contains decisionID %g not found in decisionState.', did);
            end

            di = posByDecisionId(did);

            isRelevant = logical(rc.hasRequiredContext(rr));
            relByDecision(di) = isRelevant;

            if isRelevant
                predictedReward = logical(rc.ruleSatisfied(rr));
                observedReward = humanRewarded(di);
                consByDecision(di) = (predictedReward == observedReward);
            else
                consByDecision(di) = false;
            end

            history.currentObservationEvaluated(rr) = isRelevant;
            history.currentObservationConsistent(rr) = consByDecision(di);
        end

        cRel = cumsum(double(relByDecision));
        cCon = cumsum(double(consByDecision));
        cInc = cumsum(double(relByDecision & ~consByDecision));

        for k = 1:numel(rRows)
            rr = rRows(k);
            did = double(rc.decisionID(rr));
            di = posByDecisionId(did);

            if di <= 1
                relBefore = 0;
                conBefore = 0;
                incBefore = 0;
            else
                relBefore = cRel(di - 1);
                conBefore = cCon(di - 1);
                incBefore = cInc(di - 1);
            end

            history.nRelevantObservationsBeforeDecision(rr) = relBefore;
            history.nConsistentObservationsBeforeDecision(rr) = conBefore;
            history.nInconsistentObservationsBeforeDecision(rr) = incBefore;
            history.cumulativeConsistencyBeforeDecision(rr) = safeDivideScalar(conBefore, relBefore);

            history.nHumanObservationsBeforeDecision(rr) = nHumanBefore(di);
            history.nAgentObservationsBeforeDecision(rr) = nAgentBefore(di);
            history.nRewardedObservationsBeforeDecision(rr) = nRewardedBefore(di);
            history.nUnrewardedObservationsBeforeDecision(rr) = nUnrewardedBefore(di);
        end
    end

    history = sortrows(history, {'globalDecisionIndex', 'candidateRuleName'});
end

function out = safeDivideScalar(num, den)
    if den == 0
        out = NaN;
    else
        out = num / den;
    end
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
