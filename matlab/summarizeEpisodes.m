function episodeTable = summarizeEpisodes(sessionInput)
%SUMMARIZEEPISODES Compute one descriptive row per episode.
%   T = SUMMARIZEEPISODES(SESSIONINPUT) returns a table with one row per
%   episode containing descriptive metrics only.

    session = afResolveSessionInput(sessionInput);

    startEvents = afEventsByType(session, 'episode_start');
    endEvents = afEventsByType(session, 'episode_end');
    rewardEvents = afEventsByType(session, 'reward_delivered');

    episodeNumbers = afUnionEpisodeNumbers(startEvents, endEvents, rewardEvents);
    n = numel(episodeNumbers);

    block = nan(n, 1);
    rule = strings(n, 1);
    episodeLength = nan(n, 1);
    participantScore = zeros(n, 1);
    agentScore = zeros(n, 1);
    participantRewards = zeros(n, 1);
    agentRewards = zeros(n, 1);

    for i = 1:n
        ep = episodeNumbers(i);

        start = afFindEpisodeEvent(startEvents, ep);
        stop = afFindEpisodeEvent(endEvents, ep);

        if ~isempty(start)
            d = afField(start, 'data', struct());
            block(i) = afField(d, 'blockNumber', NaN);
            phaseName = string(afField(d, 'phaseName', ""));
            ruleFile = string(afField(d, 'ruleFile', ""));
            if strlength(ruleFile) > 0
                rule(i) = ruleFile;
            else
                rule(i) = phaseName;
            end
        end

        if ~isempty(stop)
            d = afField(stop, 'data', struct());
            episodeLength(i) = afField(d, 'moveCount', NaN);
            finalScores = afField(d, 'finalScores', struct());
            participantScore(i) = afField(finalScores, 'humanScore', 0);
            agentScore(i) = afField(finalScores, 'agentScore', 0);
            if isnan(block(i))
                block(i) = afField(d, 'blockNumber', NaN);
            end
        end

        epRewardEvents = afRewardEventsForEpisode(rewardEvents, ep);
        [participantRewards(i), agentRewards(i)] = afRewardTotals(epRewardEvents);

        if isnan(episodeLength(i))
            humanMoves = numel(afMoveEventsForEpisode(session, 'human_move', ep));
            agentMoves = numel(afMoveEventsForEpisode(session, 'agent_move', ep));
            episodeLength(i) = humanMoves + agentMoves;
        end
    end

    episodeTable = table(
        episodeNumbers(:), ...
        block, ...
        rule, ...
        episodeLength, ...
        participantScore, ...
        agentScore, ...
        participantRewards, ...
        agentRewards, ...
        'VariableNames', {
            'episodeNumber', ...
            'block', ...
            'rule', ...
            'episodeLength', ...
            'participantScore', ...
            'agentScore', ...
            'participantRewards', ...
            'agentRewards'
        }
    );
end
