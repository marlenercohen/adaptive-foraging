function episodes = summarizeEpisodes(trials)
%SUMMARIZEEPISODES Build one descriptive row per episode from trial rows.
%   EPISODES = SUMMARIZEEPISODES(TRIALS) summarizes one row per episode
%   using the output table from BUILDTRIALTABLE. This function does not
%   read raw session/event logs.
%
%   Additional derived episode-level outputs include:
%     episodeLength = nHumanMoves + nAgentMoves
%     totalRewardsCollected = nHumanRewards + nAgentRewards
%     rewardFractionCollected = totalRewardsCollected ./
%         (totalRewardsCollected + rewardsRemaining)
%       (NaN when denominator is zero)
%     nHumanRepeatErrors = nHumanRepeatedOwn + nHumanRepeatedAgent
%     nAgentRepeatErrors = nAgentRepeatedOwn + nAgentRepeatedHuman
%     ruleDescription (human-readable text from rule fields)

    if nargin < 1
        error('summarizeEpisodes:MissingInput', 'trials is required.');
    end
    if ~istable(trials)
        error('summarizeEpisodes:InvalidInputType', ...
            'trials must be a table returned by buildTrialTable().');
    end

    requiredVars = {
        'block','phase','episode', ...
        'ruleName','ruleType','feature','operator','value','minimumDistance', ...
        'humanReward','humanNoRewardRuleViolation','humanRepeatedOwnLocation','humanRepeatedAgentLocation', ...
        'agentPosition','agentReward','agentNoRewardRuleViolation','agentRepeatedOwnLocation','agentRepeatedHumanLocation', ...
        'agentHumanDistance','humanDistanceFromPreviousAgent','agentDistanceFromPreviousHuman', ...
        'humanEpisodeScore','agentEpisodeScore','rewardsRemaining'
    };
    assertTableVariables(trials, requiredVars, 'summarizeEpisodes:MissingVariables');

    if isempty(trials)
        episodes = table();
        return;
    end

    [G, block, phase, episode] = findgroups(trials.block, trials.phase, trials.episode);
    nGroups = numel(episode);
    groupLabels = compose("block=%g phase=%s episode=%g", double(block), string(phase), double(episode));

    % Validate that descriptive rule fields are constant within each episode.
    validateConstantWithinEpisode(trials.ruleName, G, groupLabels, 'ruleName');
    validateConstantWithinEpisode(trials.ruleType, G, groupLabels, 'ruleType');
    validateConstantWithinEpisode(trials.feature, G, groupLabels, 'feature');
    validateConstantWithinEpisode(trials.operator, G, groupLabels, 'operator');
    validateConstantWithinEpisode(trials.value, G, groupLabels, 'value');
    validateConstantWithinEpisode(trials.minimumDistance, G, groupLabels, 'minimumDistance');

    % First-row descriptors (constant within episode by validation above).
    ruleName = splitapply(@firstValue, trials.ruleName, G);
    ruleType = splitapply(@firstValue, trials.ruleType, G);
    feature = splitapply(@firstValue, trials.feature, G);
    operator = splitapply(@firstValue, trials.operator, G);
    value = splitapply(@firstValue, trials.value, G);
    minimumDistance = splitapply(@firstValue, trials.minimumDistance, G);

    % Human performance.
    nHumanMoves = splitapply(@numel, trials.humanReward, G);
    nHumanRewards = splitapply(@(x) sum(toLogical(x)), trials.humanReward, G);
    humanRewardRate = safeDivide(nHumanRewards, nHumanMoves);

    nHumanRuleViolations = splitapply(@(x) sum(toLogical(x)), trials.humanNoRewardRuleViolation, G);
    nHumanRepeatedOwn = splitapply(@(x) sum(toLogical(x)), trials.humanRepeatedOwnLocation, G);
    nHumanRepeatedAgent = splitapply(@(x) sum(toLogical(x)), trials.humanRepeatedAgentLocation, G);

    % Agent performance from preceding-agent columns in trials.
    hasAgentMove = ~isnan(double(trials.agentPosition));
    nAgentMoves = splitapply(@(x) sum(x), hasAgentMove, G);
    nAgentRewards = splitapply(@(reward,mask) sum(toLogical(reward(mask))), trials.agentReward, hasAgentMove, G);
    agentRewardRate = safeDivide(nAgentRewards, nAgentMoves);

    nAgentRuleViolations = splitapply(@(x) sum(toLogical(x)), trials.agentNoRewardRuleViolation, G);
    nAgentRepeatedOwn = splitapply(@(x) sum(toLogical(x)), trials.agentRepeatedOwnLocation, G);
    nAgentRepeatedHuman = splitapply(@(x) sum(toLogical(x)), trials.agentRepeatedHumanLocation, G);

    % Episode size and repeat summaries.
    episodeLength = nHumanMoves + nAgentMoves;
    nHumanRepeatErrors = nHumanRepeatedOwn + nHumanRepeatedAgent;
    nAgentRepeatErrors = nAgentRepeatedOwn + nAgentRepeatedHuman;

    % Interaction metrics.
    meanAgentHumanDistance = splitapply(@meanOmitNaN, trials.agentHumanDistance, G);
    meanHumanDistanceFromPreviousAgent = splitapply(@meanOmitNaN, trials.humanDistanceFromPreviousAgent, G);
    meanAgentDistanceFromPreviousHuman = splitapply(@meanOmitNaN, trials.agentDistanceFromPreviousHuman, G);

    % Final episode state from last trial row per episode.
    rowIndex = (1:height(trials))';
    lastRowIdx = splitapply(@(x) x(end), rowIndex, G);

    finalHumanEpisodeScore = trials.humanEpisodeScore(lastRowIdx);
    finalAgentEpisodeScore = trials.agentEpisodeScore(lastRowIdx);
    rewardsRemaining = trials.rewardsRemaining(lastRowIdx);
    allRewardsCollected = rewardsRemaining == 0;

    % Reward summaries.
    totalRewardsCollected = nHumanRewards + nAgentRewards;
    rewardFractionCollected = safeDivide(totalRewardsCollected, totalRewardsCollected + rewardsRemaining);

    winner = strings(nGroups, 1);
    winner(finalHumanEpisodeScore > finalAgentEpisodeScore) = "human";
    winner(finalAgentEpisodeScore > finalHumanEpisodeScore) = "agent";
    winner(finalHumanEpisodeScore == finalAgentEpisodeScore) = "tie";

    % Human-readable rule text.
    ruleDescription = buildRuleDescription(ruleType, feature, operator, value, minimumDistance);

    % Validation: final scores must match episode maxima.
    maxHumanEpisodeScore = splitapply(@(x) max(double(x), [], 'omitnan'), trials.humanEpisodeScore, G);
    maxAgentEpisodeScore = splitapply(@(x) max(double(x), [], 'omitnan'), trials.agentEpisodeScore, G);

    badHuman = ~isequalnVector(finalHumanEpisodeScore, maxHumanEpisodeScore);
    if any(badHuman)
        idx = find(badHuman, 1, 'first');
        error('summarizeEpisodes:FinalHumanScoreMismatch', ...
            ['Episode %g finalHumanEpisodeScore (%g) does not match ', ...
             'max humanEpisodeScore in that episode (%g).'], ...
            episode(idx), finalHumanEpisodeScore(idx), maxHumanEpisodeScore(idx));
    end

    badAgent = ~isequalnVector(finalAgentEpisodeScore, maxAgentEpisodeScore);
    if any(badAgent)
        idx = find(badAgent, 1, 'first');
        error('summarizeEpisodes:FinalAgentScoreMismatch', ...
            ['Episode %g finalAgentEpisodeScore (%g) does not match ', ...
             'max agentEpisodeScore in that episode (%g).'], ...
            episode(idx), finalAgentEpisodeScore(idx), maxAgentEpisodeScore(idx));
    end

    episodes = table( ...
        block, phase, episode, ...
        ruleName, ruleType, feature, operator, value, minimumDistance, ...
        ruleDescription, ...
        nHumanMoves, nHumanRewards, humanRewardRate, ...
        nHumanRuleViolations, nHumanRepeatedOwn, nHumanRepeatedAgent, ...
        nHumanRepeatErrors, ...
        nAgentMoves, nAgentRewards, agentRewardRate, ...
        nAgentRuleViolations, nAgentRepeatedOwn, nAgentRepeatedHuman, ...
        nAgentRepeatErrors, ...
        episodeLength, ...
        totalRewardsCollected, rewardFractionCollected, ...
        meanAgentHumanDistance, ...
        meanHumanDistanceFromPreviousAgent, meanAgentDistanceFromPreviousHuman, ...
        finalHumanEpisodeScore, finalAgentEpisodeScore, rewardsRemaining, ...
        allRewardsCollected, winner);
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end

function validateConstantWithinEpisode(values, G, groupLabels, varName)
    switch class(values)
        case {'string','char'}
            isConstant = splitapply(@isConstantStringTreatMissingEqual, values, G);
        case 'cell'
            isConstant = splitapply(@isConstantStringTreatMissingEqual, values, G);
        otherwise
            isConstant = splitapply(@isConstantNumericTreatNaNEqual, values, G);
    end

    if any(~isConstant)
        idx = find(~isConstant, 1, 'first');
        error('summarizeEpisodes:InconsistentEpisodeField', ...
            'Field "%s" is not identical across all rows in %s.', ...
            varName, char(groupLabels(idx)));
    end
end

function tf = isConstantNumericTreatNaNEqual(x)
    x = double(x);
    x = x(~isnan(x));
    if isempty(x)
        tf = true;
        return;
    end
    tf = numel(unique(x)) == 1;
end

function isConstant = isConstantStringTreatMissingEqual(x)
    x = string(x);
    x = x(~ismissing(x));

    if isempty(x)
        isConstant = true;
    else
        isConstant = numel(unique(x)) == 1;
    end
end

function y = firstValue(x)
    y = x(1);
end

function m = meanOmitNaN(x)
    x = double(x);
    m = mean(x, 'omitnan');
end

function tf = toLogical(x)
    tf = logical(x);
end

function out = safeDivide(num, den)
    out = nan(size(num));
    nonzero = den ~= 0;
    out(nonzero) = num(nonzero) ./ den(nonzero);
end

function tf = isequalnVector(a, b)
    a = double(a);
    b = double(b);
    tf = (a == b) | (isnan(a) & isnan(b));
end

function desc = buildRuleDescription(ruleType, feature, operator, value, minimumDistance)
    n = numel(ruleType);
    desc = strings(n, 1);

    rt = string(ruleType);
    ft = string(feature);
    op = string(operator);
    vv = double(value);
    md = double(minimumDistance);

    for i = 1:n
        if rt(i) == "feature"
            if strlength(ft(i)) > 0 && strlength(op(i)) > 0 && ~isnan(vv(i))
                desc(i) = sprintf('%s %s %g', ft(i), op(i), vv(i));
            else
                desc(i) = "feature rule";
            end
        elseif rt(i) == "distance-from-agent"
            if ~isnan(md(i))
                desc(i) = sprintf('distance >= %g', md(i));
            else
                desc(i) = "distance rule";
            end
        else
            parts = strings(0, 1);
            if strlength(rt(i)) > 0
                parts(end+1,1) = "type=" + rt(i); %#ok<AGROW>
            end
            if strlength(ft(i)) > 0
                parts(end+1,1) = "feature=" + ft(i); %#ok<AGROW>
            end
            if strlength(op(i)) > 0
                parts(end+1,1) = "operator=" + op(i); %#ok<AGROW>
            end
            if ~isnan(vv(i))
                parts(end+1,1) = "value=" + string(vv(i)); %#ok<AGROW>
            end
            if ~isnan(md(i))
                parts(end+1,1) = "minimumDistance=" + string(md(i)); %#ok<AGROW>
            end

            if isempty(parts)
                desc(i) = "rule";
            else
                desc(i) = "rule (" + strjoin(parts, ', ') + ")";
            end
        end
    end
end
