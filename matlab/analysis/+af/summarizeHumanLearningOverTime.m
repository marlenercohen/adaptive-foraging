function [learningTable, figSession, figEpisode] = summarizeHumanLearningOverTime(episodeState)
%af.summarizeHumanLearningOverTime Descriptive human learning trajectory.
%   [LEARNINGTABLE, FIGSESSION, FIGHUMAN] =
%   af.summarizeHumanLearningOverTime(EPISODESTATE) returns one row per
%   human decision with descriptive session, episode, and cumulative
%   learning variables.
%
%   The function uses only reconstructed episode state. It does not rebuild
%   the board, re-evaluate rules, fit models, or perform statistical tests.

    if nargin < 1
        error('af:summarizeHumanLearningOverTime:MissingInput', ...
            'episodeState is required.');
    end
    if ~istable(episodeState)
        error('af:summarizeHumanLearningOverTime:InvalidInputType', ...
            'episodeState must be a table returned by af.reconstructEpisodeState().');
    end

    requiredVars = {
        'eventSeq', 'episode', 'actor', 'block', 'phase', 'trialWithinEpisode', ...
        'activeRuleName', 'activeRuleType', 'chosenStimulusID', 'chosenPositionID', ...
        'chosenReward', 'chosenRepeat', 'chosenSatisfiesRule', ...
        'availablePositionIDs', 'availableStimulusIDs', ...
        'availableMatchingPositionIDs', 'availableMatchingStimulusIDs'
    };
    assertTableVariables(episodeState, requiredVars, ...
        'af:summarizeHumanLearningOverTime:MissingEpisodeStateVariables');

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
    humanCount = nnz(humanMask);
    if humanCount == 0
        learningTable = table();
        figSession = figure('Name', 'Human learning over time', 'Color', 'w');
        annotation(figSession, 'textbox', [0.25 0.45 0.5 0.1], 'String', ...
            'No human decisions available.', 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
        figEpisode = figure('Name', 'Human learning by episode', 'Color', 'w');
        annotation(figEpisode, 'textbox', [0.25 0.45 0.5 0.1], 'String', ...
            'No human decisions available.', 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
        return;
    end

    humanState = episodeState(humanMask, :);
    learningTable = buildLearningTable(humanState, episodeState);

    figSession = figure('Name', 'Human learning over time', 'Color', 'w');
    ax1 = axes(figSession);
    hold(ax1, 'on');
    plotSessionLearning(ax1, learningTable);
    title(ax1, 'Advantage over chance across the session');
    xlabel(ax1, 'Cumulative human decision number');
    ylabel(ax1, 'Advantage over chance');

    figEpisode = figure('Name', 'Human learning by episode', 'Color', 'w');
    ax2 = axes(figEpisode);
    hold(ax2, 'on');
    plotEpisodeLearning(ax2, learningTable);
    title(ax2, 'Advantage over chance within episodes');
    xlabel(ax2, 'Decision number within episode');
    ylabel(ax2, 'Advantage over chance');
end

function learningTable = buildLearningTable(humanState, episodeState)
    humanDecisionCount = height(humanState);
    cumulativeHumanDecisionNumber = (1:humanDecisionCount)';

    episodeValues = double(humanState.episode);
    uniqueEpisodes = unique(episodeValues, 'stable');
    episodeOrdinal = zeros(humanDecisionCount, 1);
    humanDecisionSinceEpisodeStart = zeros(humanDecisionCount, 1);
    episodeStartHumanDecisionNumber = zeros(humanDecisionCount, 1);
    episodeEndHumanDecisionNumber = zeros(humanDecisionCount, 1);
    episodeDecisionCount = zeros(humanDecisionCount, 1);

    humanRowsByEpisode = cell(numel(uniqueEpisodes), 1);
    nContributingEpisodesByDecisionNumberWithinEpisode = zeros(humanDecisionCount, 1);

    for i = 1:numel(uniqueEpisodes)
        episodeNumber = uniqueEpisodes(i);
        idx = find(episodeValues == episodeNumber);
        humanRowsByEpisode{i} = idx;
        episodeOrdinal(idx) = i;
        humanDecisionSinceEpisodeStart(idx) = (1:numel(idx))';
        episodeStartHumanDecisionNumber(idx) = cumulativeHumanDecisionNumber(idx(1));
        episodeEndHumanDecisionNumber(idx) = cumulativeHumanDecisionNumber(idx(end));
        episodeDecisionCount(idx) = numel(idx);
    end

    maxDecisionWithinEpisode = max(humanDecisionSinceEpisodeStart);
    for k = 1:maxDecisionWithinEpisode
        nContributingEpisodesByDecisionNumberWithinEpisode(humanDecisionSinceEpisodeStart == k) = ...
            sum(cellfun(@(episodeIdx) numel(episodeIdx) >= k, humanRowsByEpisode));
    end

    rowCount = humanDecisionCount;
    block = double(humanState.block);
    phase = string(humanState.phase);
    activeRuleName = string(humanState.activeRuleName);
    activeRuleType = string(humanState.activeRuleType);
    trialWithinEpisode = double(humanState.trialWithinEpisode);
    chosenStimulusID = double(humanState.chosenStimulusID);
    chosenPositionID = double(humanState.chosenPositionID);
    chosenReward = double(logical(humanState.chosenReward));
    chosenRepeat = double(logical(humanState.chosenRepeat));
    chosenSatisfiesRule = double(logical(humanState.chosenSatisfiesRule));

    numberAvailableStimuli = zeros(rowCount, 1);
    numberAvailableMatchingStimuli = zeros(rowCount, 1);
    fractionAvailableMatchingRule = nan(rowCount, 1);
    advantageOverChance = nan(rowCount, 1);

    previousHumanReward = nan(rowCount, 1);
    previousAgentReward = nan(rowCount, 1);
    previousHumanRepeated = nan(rowCount, 1);
    previousAgentRepeated = nan(rowCount, 1);
    previousHumanSatisfiedRule = nan(rowCount, 1);
    previousAgentSatisfiedRule = nan(rowCount, 1);
    cumulativeHumanRewards = nan(rowCount, 1);
    cumulativeAgentRewards = nan(rowCount, 1);
    cumulativeHumanRuleSuccesses = nan(rowCount, 1);
    cumulativeAgentRuleSuccesses = nan(rowCount, 1);
    totalDecisionsSinceEpisodeStart = nan(rowCount, 1);

    currentEpisode = NaN;
    episodeHumanDecisionCount = 0;
    episodeTotalDecisionCount = 0;
    humanRewardTotal = 0;
    agentRewardTotal = 0;
    humanRuleSuccessTotal = 0;
    agentRuleSuccessTotal = 0;
    lastHumanReward = NaN;
    lastAgentReward = NaN;
    lastHumanRepeated = NaN;
    lastAgentRepeated = NaN;
    lastHumanSatisfiedRule = NaN;
    lastAgentSatisfiedRule = NaN;

    rowIndex = 0;
    for i = 1:height(episodeState)
        rowEpisode = double(episodeState.episode(i));
        if isnan(currentEpisode) || rowEpisode ~= currentEpisode
            currentEpisode = rowEpisode;
            episodeHumanDecisionCount = 0;
            episodeTotalDecisionCount = 0;
            humanRewardTotal = 0;
            agentRewardTotal = 0;
            humanRuleSuccessTotal = 0;
            agentRuleSuccessTotal = 0;
            lastHumanReward = NaN;
            lastAgentReward = NaN;
            lastHumanRepeated = NaN;
            lastAgentRepeated = NaN;
            lastHumanSatisfiedRule = NaN;
            lastAgentSatisfiedRule = NaN;
        end

        episodeTotalDecisionCount = episodeTotalDecisionCount + 1;
        isHuman = actor(i) == "human";
        reward = double(logical(episodeState.chosenReward(i)));
        repeated = double(logical(episodeState.chosenRepeat(i)));
        satisfiedRule = double(logical(episodeState.chosenSatisfiesRule(i)));

        if isHuman
            rowIndex = rowIndex + 1;
            episodeHumanDecisionCount = episodeHumanDecisionCount + 1;

            previousHumanReward(rowIndex) = lastHumanReward;
            previousAgentReward(rowIndex) = lastAgentReward;
            previousHumanRepeated(rowIndex) = lastHumanRepeated;
            previousAgentRepeated(rowIndex) = lastAgentRepeated;
            previousHumanSatisfiedRule(rowIndex) = lastHumanSatisfiedRule;
            previousAgentSatisfiedRule(rowIndex) = lastAgentSatisfiedRule;

            humanRewardTotal = humanRewardTotal + reward;
            humanRuleSuccessTotal = humanRuleSuccessTotal + satisfiedRule;

            cumulativeHumanRewards(rowIndex) = humanRewardTotal;
            cumulativeAgentRewards(rowIndex) = agentRewardTotal;
            cumulativeHumanRuleSuccesses(rowIndex) = humanRuleSuccessTotal;
            cumulativeAgentRuleSuccesses(rowIndex) = agentRuleSuccessTotal;
            totalDecisionsSinceEpisodeStart(rowIndex) = episodeTotalDecisionCount;

            availablePos = double(episodeState.availablePositionIDs{i});
            availableMatchPos = double(episodeState.availableMatchingPositionIDs{i});
            availableStim = double(episodeState.availableStimulusIDs{i});
            availableMatchStim = double(episodeState.availableMatchingStimulusIDs{i});

            if isempty(availablePos)
                error('af:summarizeHumanLearningOverTime:NoAvailableStimuli', ...
                    'Human decision row %d has no available stimuli.', i);
            end
            if numel(availablePos) ~= numel(availableStim)
                error('af:summarizeHumanLearningOverTime:AvailableStimulusMismatch', ...
                    'Human decision row %d has mismatched available position and stimulus lists.', i);
            end
            if numel(availableMatchPos) ~= numel(availableMatchStim)
                error('af:summarizeHumanLearningOverTime:MatchingStimulusMismatch', ...
                    'Human decision row %d has mismatched rule-matching available lists.', i);
            end

            numberAvailableStimuli(rowIndex) = numel(availablePos);
            numberAvailableMatchingStimuli(rowIndex) = numel(availableMatchPos);
            fractionAvailableMatchingRule(rowIndex) = numberAvailableMatchingStimuli(rowIndex) / numberAvailableStimuli(rowIndex);
            advantageOverChance(rowIndex) = chosenSatisfiesRule(rowIndex) - fractionAvailableMatchingRule(rowIndex);

            if ~any(chosenPositionID(rowIndex) == availablePos)
                error('af:summarizeHumanLearningOverTime:ChosenPositionNotAvailable', ...
                    'Human decision row %d chose position %g, which is not in availablePositionIDs.', ...
                    i, chosenPositionID(rowIndex));
            end
            chosenAvailableIndex = find(availablePos == chosenPositionID(rowIndex), 1, 'first');
            if isempty(chosenAvailableIndex) || availableStim(chosenAvailableIndex) ~= chosenStimulusID(rowIndex)
                error('af:summarizeHumanLearningOverTime:ChosenStimulusMismatch', ...
                    'Human decision row %d has a chosen stimulus that does not match the available-state mapping.', i);
            end

            if fractionAvailableMatchingRule(rowIndex) < 0 || fractionAvailableMatchingRule(rowIndex) > 1
                error('af:summarizeHumanLearningOverTime:InvalidAvailableFraction', ...
                    'Human decision row %d has fractionAvailableMatchingRule outside [0, 1].', i);
            end
        end

        if isHuman
            lastHumanReward = reward;
            lastHumanRepeated = repeated;
            lastHumanSatisfiedRule = satisfiedRule;
        else
            agentRewardTotal = agentRewardTotal + reward;
            agentRuleSuccessTotal = agentRuleSuccessTotal + satisfiedRule;
            lastAgentReward = reward;
            lastAgentRepeated = repeated;
            lastAgentSatisfiedRule = satisfiedRule;
        end
    end

    learningTable = table();
    if ismember('decisionID', humanState.Properties.VariableNames)
        learningTable.decisionID = double(humanState.decisionID);
    end
    if ismember('globalDecisionIndex', humanState.Properties.VariableNames)
        learningTable.globalDecisionIndex = double(humanState.globalDecisionIndex);
    end

    learningTable.cumulativeHumanDecisionNumber = cumulativeHumanDecisionNumber;
    learningTable.episode = episodeValues;
    learningTable.episodeOrdinal = episodeOrdinal;
    learningTable.decisionNumberWithinEpisode = humanDecisionSinceEpisodeStart;
    learningTable.humanDecisionSinceEpisodeStart = humanDecisionSinceEpisodeStart;
    learningTable.totalDecisionsSinceEpisodeStart = totalDecisionsSinceEpisodeStart;
    learningTable.episodeDecisionCount = episodeDecisionCount;
    learningTable.episodeStartHumanDecisionNumber = episodeStartHumanDecisionNumber;
    learningTable.episodeEndHumanDecisionNumber = episodeEndHumanDecisionNumber;
    learningTable.nContributingEpisodesByDecisionNumberWithinEpisode = nContributingEpisodesByDecisionNumberWithinEpisode;
    learningTable.block = block;
    learningTable.phase = phase;
    learningTable.activeRuleName = activeRuleName;
    learningTable.activeRuleType = activeRuleType;
    learningTable.trialWithinEpisode = trialWithinEpisode;
    learningTable.chosenStimulusID = chosenStimulusID;
    learningTable.chosenPositionID = chosenPositionID;
    learningTable.chosenReward = logical(chosenReward);
    learningTable.chosenRepeat = logical(chosenRepeat);
    learningTable.chosenSatisfiesRule = logical(chosenSatisfiesRule);
    learningTable.previousHumanReward = previousHumanReward;
    learningTable.previousAgentReward = previousAgentReward;
    learningTable.previousHumanRepeated = previousHumanRepeated;
    learningTable.previousAgentRepeated = previousAgentRepeated;
    learningTable.previousHumanSatisfiedRule = previousHumanSatisfiedRule;
    learningTable.previousAgentSatisfiedRule = previousAgentSatisfiedRule;
    learningTable.cumulativeHumanRewards = cumulativeHumanRewards;
    learningTable.cumulativeAgentRewards = cumulativeAgentRewards;
    learningTable.cumulativeHumanRuleSuccesses = cumulativeHumanRuleSuccesses;
    learningTable.cumulativeAgentRuleSuccesses = cumulativeAgentRuleSuccesses;
    learningTable.numberAvailableStimuli = numberAvailableStimuli;
    learningTable.numberAvailableMatchingStimuli = numberAvailableMatchingStimuli;
    learningTable.fractionAvailableMatchingRule = fractionAvailableMatchingRule;
    learningTable.advantageOverChance = advantageOverChance;
    learningTable.availablePositionIDs = humanState.availablePositionIDs;
    learningTable.availableStimulusIDs = humanState.availableStimulusIDs;
    learningTable.availableMatchingPositionIDs = humanState.availableMatchingPositionIDs;
    learningTable.availableMatchingStimulusIDs = humanState.availableMatchingStimulusIDs;

    if ismember('sessionID', humanState.Properties.VariableNames)
        learningTable.sessionID = humanState.sessionID;
    end
    if ismember('participantID', humanState.Properties.VariableNames)
        learningTable.participantID = humanState.participantID;
    end

    figSession = figure('Name', 'Human learning over time', 'Color', 'w');
    ax1 = axes(figSession);
    hold(ax1, 'on');
    plotSessionLearning(ax1, learningTable);
    title(ax1, 'Advantage over chance across the session');
    xlabel(ax1, 'Cumulative human decision number');
    ylabel(ax1, 'Advantage over chance');

    figEpisode = figure('Name', 'Human learning by episode', 'Color', 'w');
    ax2 = axes(figEpisode);
    hold(ax2, 'on');
    plotEpisodeLearning(ax2, learningTable);
    title(ax2, 'Advantage over chance within episodes');
    xlabel(ax2, 'Decision number within episode');
    ylabel(ax2, 'Advantage over chance');
end

function plotSessionLearning(ax, learningTable)
    episodeOrdinals = unique(learningTable.episodeOrdinal, 'stable');
    if isempty(episodeOrdinals)
        return;
    end

    sessionX = learningTable.cumulativeHumanDecisionNumber;
    sessionY = learningTable.advantageOverChance;
    movingAverage = computeMovingAverage(sessionY);

    yMin = min([sessionY; movingAverage]);
    yMax = max([sessionY; movingAverage]);
    if yMin == yMax
        padding = max(0.1, abs(yMin) * 0.1 + 0.1);
    else
        padding = 0.08 * (yMax - yMin);
    end
    yLow = min(0, yMin) - padding;
    yHigh = max(0, yMax) + padding;

    for i = 1:numel(episodeOrdinals)
        idx = learningTable.episodeOrdinal == episodeOrdinals(i);
        firstIdx = find(idx, 1, 'first');
        lastIdx = find(idx, 1, 'last');
        startX = learningTable.episodeStartHumanDecisionNumber(firstIdx) - 0.5;
        endX = learningTable.episodeEndHumanDecisionNumber(lastIdx) + 0.5;
        if mod(i, 2) == 0
            patch(ax, [startX endX endX startX], [yLow yLow yHigh yHigh], [0.92 0.92 0.92], ...
                'EdgeColor', 'none', 'FaceAlpha', 0.45, 'HandleVisibility', 'off');
        else
            patch(ax, [startX endX endX startX], [yLow yLow yHigh yHigh], [0.97 0.97 0.97], ...
                'EdgeColor', 'none', 'FaceAlpha', 0.35, 'HandleVisibility', 'off');
        end
        if i > 1
            line(ax, [startX startX], [yLow yHigh], 'LineStyle', '--', 'Color', [0.3 0.3 0.3], ...
                'LineWidth', 1, 'HandleVisibility', 'off');
        end
    end

    line(ax, [0.5, max(sessionX) + 0.5], [0, 0], 'Color', [0.45 0.45 0.45], ...
        'LineStyle', '-', 'LineWidth', 1, 'HandleVisibility', 'off');
    scatter(ax, sessionX, sessionY, 18, 'filled', ...
        'MarkerFaceColor', [0.1 0.1 0.1], 'MarkerEdgeColor', [0.1 0.1 0.1], ...
        'MarkerFaceAlpha', 0.35, 'MarkerEdgeAlpha', 0.35);
    plot(ax, sessionX, movingAverage, '-', 'Color', [0 0.4470 0.7410], ...
        'LineWidth', 2, 'Marker', 'none');
    ylim(ax, [yLow yHigh]);
    xlim(ax, [0.5, max(sessionX) + 0.5]);
    grid(ax, 'on');
end

function plotEpisodeLearning(ax, learningTable)
    episodeOrdinals = unique(learningTable.episodeOrdinal, 'stable');
    if isempty(episodeOrdinals)
        return;
    end

    summary = computeEpisodeTrajectorySummary(learningTable);
    valid = summary.nContributingEpisodes > 0;
    if any(valid)
        x = summary.decisionNumberWithinEpisode(valid);
        meanY = summary.meanAdvantage(valid);
        semY = summary.semAdvantage(valid);
        upper = meanY + semY;
        lower = meanY - semY;
        fill(ax, [x; flipud(x)], [upper; flipud(lower)], [0 0.4470 0.7410], ...
            'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end

    for i = 1:numel(episodeOrdinals)
        idx = learningTable.episodeOrdinal == episodeOrdinals(i);
        x = learningTable.decisionNumberWithinEpisode(idx);
        y = learningTable.advantageOverChance(idx);
        plot(ax, x, y, '-', 'Color', [0.78 0.78 0.78], 'LineWidth', 0.75, 'HandleVisibility', 'off');
    end

    if any(valid)
        plot(ax, x, meanY, '-', 'Color', [0 0.4470 0.7410], ...
            'LineWidth', 2.5, 'Marker', 'none');
    end

    grid(ax, 'on');
    xlim(ax, [0.5, max(summary.decisionNumberWithinEpisode) + 0.5]);
end

function movingAverage = computeMovingAverage(values)
    n = numel(values);
    movingAverage = nan(n, 1);
    if n == 0
        return;
    end
    windowSize = min(n, 11);
    if mod(windowSize, 2) == 0 && windowSize > 1
        windowSize = windowSize - 1;
    end
    halfWindow = floor(windowSize / 2);
    for i = 1:n
        lo = max(1, i - halfWindow);
        hi = min(n, i + halfWindow);
        windowValues = values(lo:hi);
        windowValues = windowValues(isfinite(windowValues));
        if isempty(windowValues)
            movingAverage(i) = NaN;
        else
            movingAverage(i) = mean(windowValues);
        end
    end
end

function summary = computeEpisodeTrajectorySummary(learningTable)
    maxDecisionWithinEpisode = max(learningTable.decisionNumberWithinEpisode);
    decisionNumberWithinEpisode = (1:maxDecisionWithinEpisode)';
    meanAdvantage = nan(maxDecisionWithinEpisode, 1);
    semAdvantage = nan(maxDecisionWithinEpisode, 1);
    nContributingEpisodes = zeros(maxDecisionWithinEpisode, 1);

    for k = 1:maxDecisionWithinEpisode
        idx = learningTable.decisionNumberWithinEpisode == k;
        values = learningTable.advantageOverChance(idx);
        values = values(isfinite(values));
        nContributingEpisodes(k) = numel(values);
        if isempty(values)
            continue;
        end
        meanAdvantage(k) = mean(values);
        if numel(values) > 1
            semAdvantage(k) = std(values, 0) / sqrt(numel(values));
        else
            semAdvantage(k) = 0;
        end
    end

    summary = table(decisionNumberWithinEpisode, meanAdvantage, semAdvantage, nContributingEpisodes, ...
        'VariableNames', {'decisionNumberWithinEpisode', 'meanAdvantage', 'semAdvantage', 'nContributingEpisodes'});
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
