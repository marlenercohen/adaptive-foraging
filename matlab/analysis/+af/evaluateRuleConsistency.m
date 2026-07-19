function ruleConsistency = evaluateRuleConsistency(decisionState, stimulusMetadata, rules)
%af.evaluateRuleConsistency Objective decision x rule consistency table.
%   RULECONSISTENCY = af.evaluateRuleConsistency(DECISIONSTATE,
%   STIMULUSMETADATA, RULES) evaluates every human decision against every
%   candidate rule and returns one long-format row per:
%
%       human decision x candidate rule
%
%   This function is intentionally model-agnostic. It does not infer
%   beliefs, evidence, or latent learning states.

    if nargin < 3
        error('af:evaluateRuleConsistency:MissingInput', ...
            'decisionState, stimulusMetadata, and rules are required.');
    end
    if ~istable(decisionState)
        error('af:evaluateRuleConsistency:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end
    if ~istable(stimulusMetadata)
        error('af:evaluateRuleConsistency:InvalidStimulusMetadataType', ...
            'stimulusMetadata must be a table.');
    end
    if ~istable(rules)
        error('af:evaluateRuleConsistency:InvalidRulesType', ...
            'rules must be a table (for example from buildRuleTable).');
    end

    requiredDecisionVars = {
        'decisionID', ...
        'globalDecisionIndex', ...
        'block', 'phase', 'episode', ...
        'ruleName', ...
        'currentHumanStimulusID', ...
        'currentHumanPosition', ...
        'previousAgentPosition'
    };
    assertTableVariables(decisionState, requiredDecisionVars, ...
        'af:evaluateRuleConsistency:MissingDecisionStateVariables');

    requiredStimulusVars = {'stimulusID'};
    assertTableVariables(stimulusMetadata, requiredStimulusVars, ...
        'af:evaluateRuleConsistency:MissingStimulusMetadataVariables');

    requiredRuleVars = {'ruleName', 'ruleType', 'feature', 'operator', 'value', 'minimumDistance'};
    assertTableVariables(rules, requiredRuleVars, ...
        'af:evaluateRuleConsistency:MissingRuleVariables');

    if isempty(decisionState) || isempty(rules)
        ruleConsistency = table();
        return;
    end

    ruleTypes = string(rules.ruleType);
    hasDistanceRule = any(ruleTypes == "distance-from-agent");
    if hasDistanceRule && ~ismember('boardColumnCount', decisionState.Properties.VariableNames)
        error('af:evaluateRuleConsistency:MissingBoardColumnCount', ...
            ['decisionState is missing required Layer-2 field "boardColumnCount" ', ...
             'for evaluating distance-from-agent rules. Add board geometry to ', ...
             'Layer 2 (sourced from immutable Layer-1 task metadata) rather than ', ...
             'reconstructing it inside Layer 3.']);
    end

    ds = decisionState;
    ds.activeRuleName = string(ds.ruleName);

    ruleTbl = rules;
    ruleTbl.ruleName = string(ruleTbl.ruleName);
    ruleTbl.ruleType = string(ruleTbl.ruleType);
    ruleTbl.feature = string(ruleTbl.feature);
    ruleTbl.operator = string(ruleTbl.operator);

    joined = table();
    joined.decisionID = ds.decisionID;
    joined.globalDecisionIndex = ds.globalDecisionIndex;
    joined.block = ds.block;
    joined.phase = ds.phase;
    joined.episode = ds.episode;
    joined.activeRuleName = ds.activeRuleName;
    joined.currentHumanStimulusID = ds.currentHumanStimulusID;
    joined.currentHumanPosition = ds.currentHumanPosition;
    joined.previousAgentPosition = ds.previousAgentPosition;
    if hasDistanceRule
        joined.boardColumnCount = ds.boardColumnCount;
    else
        joined.boardColumnCount = nan(height(ds), 1);
    end

    joined = innerjoin(joined, stimulusMetadata, 'LeftKeys', 'currentHumanStimulusID', 'RightKeys', 'stimulusID');
    if height(joined) ~= height(ds)
        error('af:evaluateRuleConsistency:UnknownStimulusID', ...
            ['Some currentHumanStimulusID values in decisionState are missing from ', ...
             'stimulusMetadata. Ensure Layer-1 facts and stimulus metadata align.']);
    end

    nD = height(joined);
    nR = height(ruleTbl);
    n = nD * nR;

    dIdx = repelem((1:nD)', nR, 1);
    rIdx = repmat((1:nR)', nD, 1);

    out = table();
    out.decisionID = joined.decisionID(dIdx);
    out.globalDecisionIndex = joined.globalDecisionIndex(dIdx);
    out.block = joined.block(dIdx);
    out.phase = joined.phase(dIdx);
    out.episode = joined.episode(dIdx);
    out.activeRuleName = joined.activeRuleName(dIdx);

    out.currentHumanStimulusID = joined.currentHumanStimulusID(dIdx);
    out.currentHumanPosition = joined.currentHumanPosition(dIdx);
    out.previousAgentPosition = joined.previousAgentPosition(dIdx);

    out.candidateRuleName = ruleTbl.ruleName(rIdx);
    out.candidateRuleType = ruleTbl.ruleType(rIdx);
    out.candidateFeature = ruleTbl.feature(rIdx);
    out.candidateOperator = ruleTbl.operator(rIdx);
    out.candidateValue = ruleTbl.value(rIdx);
    out.candidateMinimumDistance = ruleTbl.minimumDistance(rIdx);

    out.isCandidateActiveRule = out.candidateRuleName == out.activeRuleName;

    out.selectedFeatureValueNumeric = nan(n, 1);
    out.selectedFeatureValueText = strings(n, 1);
    out.comparisonValue = nan(n, 1);
    out.thresholdValue = nan(n, 1);
    out.operatorResult = false(n, 1);
    out.ruleSatisfied = false(n, 1);
    out.distanceFromThreshold = nan(n, 1);
    out.hasRequiredContext = false(n, 1);

    featureRules = (out.candidateRuleType == "feature");
    distanceRules = (out.candidateRuleType == "distance-from-agent");

    if any(featureRules)
        featureNames = unique(out.candidateFeature(featureRules));
        for fi = 1:numel(featureNames)
            fname = featureNames(fi);
            if strlength(fname) == 0 || ismissing(fname)
                continue;
            end
            colName = char(fname);
            if ~ismember(colName, joined.Properties.VariableNames)
                error('af:evaluateRuleConsistency:MissingStimulusFeature', ...
                    ['Stimulus metadata is missing feature column "%s" required ', ...
                     'by one or more candidate feature rules.'], colName);
            end
        end

        featureIdx = find(featureRules);
        for k = 1:numel(featureIdx)
            row = featureIdx(k);
            di = dIdx(row);
            ri = rIdx(row);

            fname = char(ruleTbl.feature(ri));
            rawValue = joined.(fname)(di);
            [actualNum, actualText] = toComparableValue(rawValue);

            op = char(ruleTbl.operator(ri));
            target = double(ruleTbl.value(ri));

            out.selectedFeatureValueNumeric(row) = actualNum;
            out.selectedFeatureValueText(row) = actualText;
            out.comparisonValue(row) = actualNum;
            out.thresholdValue(row) = target;
            out.hasRequiredContext(row) = ~isnan(actualNum) && ~isnan(target);

            if out.hasRequiredContext(row)
                tf = evaluateOperator(actualNum, op, target);
                out.operatorResult(row) = tf;
                out.ruleSatisfied(row) = tf;
                out.distanceFromThreshold(row) = computeFeatureDistanceFromThreshold(actualNum, op, target);
            end
        end
    end

    if any(distanceRules)
        distanceIdx = find(distanceRules);
        for k = 1:numel(distanceIdx)
            row = distanceIdx(k);
            di = dIdx(row);
            ri = rIdx(row);

            posHuman = double(joined.currentHumanPosition(di));
            posAgent = double(joined.previousAgentPosition(di));
            cols = double(joined.boardColumnCount(di));
            minDist = double(ruleTbl.minimumDistance(ri));

            out.thresholdValue(row) = minDist;

            if isnan(posHuman) || isnan(posAgent) || isnan(cols) || cols <= 0 || isnan(minDist)
                out.hasRequiredContext(row) = false;
                out.operatorResult(row) = false;
                out.ruleSatisfied(row) = false;
                continue;
            end

            d = computeManhattanDistance(posHuman, posAgent, cols);
            out.comparisonValue(row) = d;
            out.hasRequiredContext(row) = true;
            out.operatorResult(row) = d >= minDist;
            out.ruleSatisfied(row) = out.operatorResult(row);
            out.distanceFromThreshold(row) = d - minDist;
        end
    end

    unknownRule = ~(featureRules | distanceRules);
    if any(unknownRule)
        badType = string(out.candidateRuleType(find(unknownRule, 1, 'first')));
        error('af:evaluateRuleConsistency:UnsupportedRuleType', ...
            'Unsupported candidate rule type "%s".', badType);
    end

    ruleConsistency = out;
end

function [valueNum, valueText] = toComparableValue(raw)
    if iscell(raw)
        raw = raw{1};
    end

    if isstring(raw)
        s = string(raw);
        if isempty(s)
            valueText = "";
            valueNum = NaN;
            return;
        end
        valueText = s(1);
        valueNum = str2double(valueText);
        return;
    end

    if ischar(raw)
        valueText = string(raw);
        valueNum = str2double(valueText);
        return;
    end

    if iscategorical(raw)
        valueText = string(raw);
        valueNum = str2double(valueText);
        return;
    end

    if isnumeric(raw) || islogical(raw)
        if isempty(raw)
            valueNum = NaN;
            valueText = "";
        else
            valueNum = double(raw(1));
            valueText = string(valueNum);
        end
        return;
    end

    valueText = string(raw);
    valueNum = NaN;
end

function tf = evaluateOperator(actual, operator, target)
    switch operator
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
            error('af:evaluateRuleConsistency:UnsupportedOperator', ...
                'Unsupported operator "%s" in candidate feature rule.', operator);
    end
end

function d = computeFeatureDistanceFromThreshold(actual, operator, target)
    switch operator
        case {'>','>='}
            d = actual - target;
        case {'<','<='}
            d = target - actual;
        case {'==','~='}
            d = abs(actual - target);
        otherwise
            d = NaN;
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

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
