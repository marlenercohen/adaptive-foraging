function out = summarizeRuleBehavior(decisionState, stimulusMetadata)
%af.summarizeRuleBehavior Descriptive behavior summaries by rule.
%   OUT = af.summarizeRuleBehavior(DECISIONSTATE, STIMULUSMETADATA)
%   returns descriptive summaries of human behavior for each rule.
%
%   This function is intentionally model-agnostic and does not compute
%   beliefs, evidence, latent values, learning rates, or uncertainty.
%
%   Output struct fields:
%     - ruleSummary: one row per rule with counts/rates and half-split stats
%     - ruleTimecourse: one row per decision with within-rule trajectories
%     - ruleFeatureSelections: rule x feature x feature-value summaries
%     - ruleEpisodeSummary: one row per (rule, episode)

    if nargin < 2
        error('af:summarizeRuleBehavior:MissingInput', ...
            'decisionState and stimulusMetadata are required.');
    end
    if ~istable(decisionState)
        error('af:summarizeRuleBehavior:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end
    if ~istable(stimulusMetadata)
        error('af:summarizeRuleBehavior:InvalidStimulusMetadataType', ...
            'stimulusMetadata must be a table.');
    end

    requiredDecisionVars = {
        'globalDecisionIndex', ...
        'block', 'phase', 'episode', ...
        'ruleName', 'ruleType', 'feature', 'operator', 'value', 'minimumDistance', ...
        'currentHumanStimulusID', 'currentHumanReward', ...
        'humanRepeatedOwnLocation', 'humanRepeatedAgentLocation'
    };
    assertTableVariables(decisionState, requiredDecisionVars, ...
        'af:summarizeRuleBehavior:MissingDecisionStateVariables');

    requiredStimulusVars = {'stimulusID'};
    assertTableVariables(stimulusMetadata, requiredStimulusVars, ...
        'af:summarizeRuleBehavior:MissingStimulusMetadataVariables');

    if isempty(decisionState)
        out = struct();
        out.ruleSummary = table();
        out.ruleTimecourse = table();
        out.ruleFeatureSelections = table();
        out.ruleEpisodeSummary = table();
        return;
    end

    ds = decisionState;
    ds.ruleName = string(ds.ruleName);
    ds.ruleType = string(ds.ruleType);
    ds.feature = string(ds.feature);
    ds.operator = string(ds.operator);

    [~, ord] = sort(double(ds.globalDecisionIndex));
    ds = ds(ord, :);

    isReward = logical(ds.currentHumanReward);
    isRepeat = logical(ds.humanRepeatedOwnLocation) | logical(ds.humanRepeatedAgentLocation);

    % Build per-rule sequential trajectories in decision order.
    n = height(ds);
    withinRuleDecisionIndex = zeros(n, 1);
    cumulativeRewardRateWithinRule = nan(n, 1);
    cumulativeRepeatRateWithinRule = nan(n, 1);
    halfLabel = strings(n, 1);

    [G, ruleName, ruleType, feature, operator, value, minimumDistance] = findgroups( ...
        ds.ruleName, ds.ruleType, ds.feature, ds.operator, ds.value, ds.minimumDistance);

    groupIds = unique(G);
    ruleSummaryRows = repmat(makeRuleSummaryRow(), 0, 1);

    for gi = 1:numel(groupIds)
        idx = find(G == groupIds(gi));
        idx = idx(:);

        m = numel(idx);
        rewards = double(isReward(idx));
        repeats = double(isRepeat(idx));

        withinRuleDecisionIndex(idx) = (1:m)';
        cumulativeRewardRateWithinRule(idx) = cumsum(rewards) ./ (1:m)';
        cumulativeRepeatRateWithinRule(idx) = cumsum(repeats) ./ (1:m)';

        splitPoint = ceil(m / 2);
        halfLabel(idx(1:splitPoint)) = "first";
        if splitPoint < m
            halfLabel(idx((splitPoint + 1):m)) = "second";
        end

        firstIdx = idx(halfLabel(idx) == "first");
        secondIdx = idx(halfLabel(idx) == "second");

        firstHalfRewardRate = mean(double(isReward(firstIdx)), 'omitnan');
        secondHalfRewardRate = mean(double(isReward(secondIdx)), 'omitnan');
        firstHalfRepeatRate = mean(double(isRepeat(firstIdx)), 'omitnan');
        secondHalfRepeatRate = mean(double(isRepeat(secondIdx)), 'omitnan');

        row = makeRuleSummaryRow();
        row.ruleName = ruleName(gi);
        row.ruleType = ruleType(gi);
        row.feature = feature(gi);
        row.operator = operator(gi);
        row.value = value(gi);
        row.minimumDistance = minimumDistance(gi);

        row.nHumanDecisions = m;
        row.nRewardedDecisions = sum(rewards);
        row.rewardRate = safeDivideScalar(row.nRewardedDecisions, row.nHumanDecisions);

        row.nRepeatSelections = sum(repeats);
        row.repeatRate = safeDivideScalar(row.nRepeatSelections, row.nHumanDecisions);

        row.firstHalfN = numel(firstIdx);
        row.secondHalfN = numel(secondIdx);
        row.firstHalfRewardRate = firstHalfRewardRate;
        row.secondHalfRewardRate = secondHalfRewardRate;
        row.rewardRateSecondMinusFirst = secondHalfRewardRate - firstHalfRewardRate;
        row.firstHalfRepeatRate = firstHalfRepeatRate;
        row.secondHalfRepeatRate = secondHalfRepeatRate;

        row.nEpisodesCovered = numel(unique(double(ds.episode(idx))));

        ruleSummaryRows(end + 1, 1) = row; %#ok<AGROW>
    end

    ruleSummary = struct2table(ruleSummaryRows);

    ruleTimecourse = table();
    ruleTimecourse.globalDecisionIndex = ds.globalDecisionIndex;
    ruleTimecourse.block = ds.block;
    ruleTimecourse.phase = ds.phase;
    ruleTimecourse.episode = ds.episode;
    ruleTimecourse.ruleName = ds.ruleName;
    ruleTimecourse.ruleType = ds.ruleType;
    ruleTimecourse.feature = ds.feature;
    ruleTimecourse.operator = ds.operator;
    ruleTimecourse.value = ds.value;
    ruleTimecourse.minimumDistance = ds.minimumDistance;
    ruleTimecourse.withinRuleDecisionIndex = withinRuleDecisionIndex;
    ruleTimecourse.half = halfLabel;
    ruleTimecourse.currentHumanStimulusID = ds.currentHumanStimulusID;
    ruleTimecourse.rewarded = isReward;
    ruleTimecourse.repeatedSelection = isRepeat;
    ruleTimecourse.cumulativeRewardRateWithinRule = cumulativeRewardRateWithinRule;
    ruleTimecourse.cumulativeRepeatRateWithinRule = cumulativeRepeatRateWithinRule;

    ruleEpisodeSummary = summarizeRuleEpisodes(ds, isReward, isRepeat);
    ruleFeatureSelections = summarizeRuleFeatureSelections(ds, isReward, stimulusMetadata);

    out = struct();
    out.ruleSummary = sortrows(ruleSummary, {'ruleName'});
    out.ruleTimecourse = sortrows(ruleTimecourse, {'globalDecisionIndex'});
    out.ruleFeatureSelections = sortrows(ruleFeatureSelections, {'ruleName','featureName','featureValue'});
    out.ruleEpisodeSummary = sortrows(ruleEpisodeSummary, {'ruleName','episode'});
end

function tbl = summarizeRuleEpisodes(ds, isReward, isRepeat)
    [G, ruleName, ruleType, feature, operator, value, minimumDistance, block, phase, episode] = findgroups( ...
        ds.ruleName, ds.ruleType, ds.feature, ds.operator, ds.value, ds.minimumDistance, ds.block, ds.phase, ds.episode);

    nDecisions = splitapply(@numel, ds.globalDecisionIndex, G);
    nRewarded = splitapply(@(x) sum(double(x)), isReward, G);
    nRepeats = splitapply(@(x) sum(double(x)), isRepeat, G);

    tbl = table();
    tbl.ruleName = ruleName;
    tbl.ruleType = ruleType;
    tbl.feature = feature;
    tbl.operator = operator;
    tbl.value = value;
    tbl.minimumDistance = minimumDistance;
    tbl.block = block;
    tbl.phase = phase;
    tbl.episode = episode;
    tbl.nHumanDecisions = nDecisions;
    tbl.nRewardedDecisions = nRewarded;
    tbl.rewardRate = safeDivideVector(nRewarded, nDecisions);
    tbl.nRepeatSelections = nRepeats;
    tbl.repeatRate = safeDivideVector(nRepeats, nDecisions);
end

function tbl = summarizeRuleFeatureSelections(ds, isReward, stimulusMetadata)
    % Keep only stimulus columns that can be represented as scalar labels.
    candidateVars = stimulusMetadata.Properties.VariableNames;
    candidateVars = candidateVars(~strcmp(candidateVars, 'stimulusID'));

    keepVar = false(size(candidateVars));
    for i = 1:numel(candidateVars)
        v = stimulusMetadata.(candidateVars{i});
        keepVar(i) = isFeatureColumn(v);
    end
    featureVars = candidateVars(keepVar);

    selectTbl = table();
    selectTbl.stimulusID = double(ds.currentHumanStimulusID);
    selectTbl.ruleName = string(ds.ruleName);
    selectTbl.rewarded = logical(isReward);

    joined = innerjoin(selectTbl, stimulusMetadata, 'Keys', 'stimulusID');
    if height(joined) ~= height(selectTbl)
        error('af:summarizeRuleBehavior:UnknownStimulusID', ...
            ['Some currentHumanStimulusID values are missing from stimulusMetadata. ', ...
             'Ensure Layer-1 facts and stimulus metadata are aligned.']);
    end

    longRows = repmat(makeFeatureRow(), 0, 1);
    for i = 1:numel(featureVars)
        varName = featureVars{i};
        values = normalizeFeatureValues(joined.(varName));

        featureTbl = table();
        featureTbl.ruleName = joined.ruleName;
        featureTbl.featureName = repmat(string(varName), height(joined), 1);
        featureTbl.featureValue = values;
        featureTbl.rewarded = joined.rewarded;

        [G, ruleName, featureName, featureValue] = findgroups(featureTbl.ruleName, featureTbl.featureName, featureTbl.featureValue);
        nSelections = splitapply(@numel, featureTbl.rewarded, G);
        nRewards = splitapply(@(x) sum(double(x)), featureTbl.rewarded, G);

        for k = 1:numel(nSelections)
            row = makeFeatureRow();
            row.ruleName = ruleName(k);
            row.featureName = featureName(k);
            row.featureValue = featureValue(k);
            row.nSelections = nSelections(k);
            row.nRewardedSelections = nRewards(k);
            row.rewardRate = safeDivideScalar(nRewards(k), nSelections(k));
            longRows(end + 1, 1) = row; %#ok<AGROW>
        end
    end

    tbl = struct2table(longRows);
end

function tf = isFeatureColumn(v)
    if isnumeric(v) || islogical(v) || isstring(v) || iscategorical(v)
        tf = true;
        return;
    end
    if iscell(v)
        tf = all(cellfun(@(x) ischar(x) || isstring(x) || isnumeric(x) || islogical(x), v));
        return;
    end
    if ischar(v)
        tf = true;
        return;
    end
    tf = false;
end

function values = normalizeFeatureValues(v)
    if isnumeric(v) || islogical(v)
        values = string(v);
        return;
    end
    if isstring(v)
        values = v;
        return;
    end
    if iscategorical(v)
        values = string(v);
        return;
    end
    if ischar(v)
        values = repmat(string(v), 1, 1);
        return;
    end
    if iscell(v)
        values = strings(numel(v), 1);
        for i = 1:numel(v)
            values(i) = string(v{i});
        end
        return;
    end

    error('af:summarizeRuleBehavior:UnsupportedFeatureType', ...
        'Unsupported stimulus metadata feature type: %s', class(v));
end

function row = makeRuleSummaryRow()
    row = struct( ...
        'ruleName', "", ...
        'ruleType', "", ...
        'feature', "", ...
        'operator', "", ...
        'value', NaN, ...
        'minimumDistance', NaN, ...
        'nHumanDecisions', 0, ...
        'nRewardedDecisions', 0, ...
        'rewardRate', NaN, ...
        'nRepeatSelections', 0, ...
        'repeatRate', NaN, ...
        'firstHalfN', 0, ...
        'secondHalfN', 0, ...
        'firstHalfRewardRate', NaN, ...
        'secondHalfRewardRate', NaN, ...
        'rewardRateSecondMinusFirst', NaN, ...
        'firstHalfRepeatRate', NaN, ...
        'secondHalfRepeatRate', NaN, ...
        'nEpisodesCovered', 0 ...
    );
end

function row = makeFeatureRow()
    row = struct( ...
        'ruleName', "", ...
        'featureName', "", ...
        'featureValue', "", ...
        'nSelections', 0, ...
        'nRewardedSelections', 0, ...
        'rewardRate', NaN ...
    );
end

function out = safeDivideScalar(num, den)
    if den == 0
        out = NaN;
    else
        out = num / den;
    end
end

function out = safeDivideVector(num, den)
    out = nan(size(num));
    nonzero = den ~= 0;
    out(nonzero) = num(nonzero) ./ den(nonzero);
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
