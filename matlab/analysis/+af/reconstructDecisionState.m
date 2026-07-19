function decisionState = reconstructDecisionState(canonicalState)
%af.reconstructDecisionState Reconstruct objective pre-decision state.
%   DECISIONSTATE = af.reconstructDecisionState(CANONICALSTATE) returns one
%   row per human decision describing what is objectively true immediately
%   before that decision.
%
%   Inputs come from Layer 1 facts. This function intentionally excludes any
%   model-dependent constructs such as beliefs, evidence, flexibility, or
%   latent learning variables.

    if nargin < 1
        error('af:reconstructDecisionState:MissingInput', 'canonicalState is required.');
    end
    if ~isstruct(canonicalState) || ~isfield(canonicalState, 'facts') || ~isfield(canonicalState.facts, 'trials')
        error('af:reconstructDecisionState:InvalidInput', ...
            'canonicalState must be produced by af.buildCanonicalState().');
    end

    trials = canonicalState.facts.trials;
    if isempty(trials)
        decisionState = table();
        return;
    end

    n = height(trials);

    % Episode-level accumulators over completed moves before the current
    % human decision. These are objective counters, not behavioral metrics.
    humanMovesBefore = zeros(n, 1);
    agentMovesBefore = zeros(n, 1);
    humanRewardsBefore = zeros(n, 1);
    agentRewardsBefore = zeros(n, 1);
    previousHumanPosition = nan(n, 1);
    previousHumanStimulusID = nan(n, 1);

    % Preceding agent fields are already aligned in each trial row.
    previousAgentPosition = trials.agentPosition;
    previousAgentStimulusID = trials.agentStimulusID;

    % Objective pre-decision rewards remaining can be reconstructed from the
    % post-decision value because each row is anchored after the human move.
    rewardsRemainingBefore = double(trials.rewardsRemaining) + double(logical(trials.humanReward));

    decisionInEpisode = nan(n, 1);
    isFirstDecisionInEpisode = false(n, 1);
    ruleChangedFromPreviousDecision = false(n, 1);

    [G, ~, ~, ~] = findgroups(trials.block, trials.phase, trials.episode);
    groupIds = unique(G);

    for gi = 1:numel(groupIds)
        idx = find(G == groupIds(gi));

        % Per-episode running state before each decision.
        hm = 0;
        am = 0;
        hr = 0;
        ar = 0;
        lastHumanPos = NaN;
        lastHumanStim = NaN;

        for k = 1:numel(idx)
            i = idx(k);

            humanMovesBefore(i) = hm;
            agentMovesBefore(i) = am;
            humanRewardsBefore(i) = hr;
            agentRewardsBefore(i) = ar;
            previousHumanPosition(i) = lastHumanPos;
            previousHumanStimulusID(i) = lastHumanStim;

            decisionInEpisode(i) = k;
            isFirstDecisionInEpisode(i) = (k == 1);

            if k > 1
                prev = idx(k - 1);
                ruleChangedFromPreviousDecision(i) = ~isequaln(string(trials.ruleName(i)), string(trials.ruleName(prev)));
            end

            % Update counters using moves that occurred before the next
            % human decision. The current row includes one human move and,
            % when present, one preceding agent move.
            hm = hm + 1;
            hr = hr + double(logical(trials.humanReward(i)));

            hasAgentMove = ~isnan(double(trials.agentPosition(i)));
            if hasAgentMove
                am = am + 1;
                ar = ar + double(logical(trials.agentReward(i)));
            end

            lastHumanPos = double(trials.humanPosition(i));
            lastHumanStim = double(trials.humanStimulusID(i));
        end
    end

    decisionState = table();
    decisionState.decisionID = trials.decisionID;
    decisionState.globalDecisionIndex = trials.globalDecisionIndex;

    % Episode/task location.
    decisionState.block = trials.block;
    decisionState.phase = trials.phase;
    decisionState.episode = trials.episode;
    decisionState.trialWithinEpisode = trials.trialWithinEpisode;
    decisionState.humanDecisionIndexEpisode = decisionInEpisode;
    decisionState.humanSelectionNumber = trials.humanSelectionNumber;

    % Objective rule context before decision.
    decisionState.ruleName = trials.ruleName;
    decisionState.ruleType = trials.ruleType;
    decisionState.feature = trials.feature;
    decisionState.operator = trials.operator;
    decisionState.value = trials.value;
    decisionState.minimumDistance = trials.minimumDistance;
    decisionState.ruleChangedFromPreviousDecision = ruleChangedFromPreviousDecision;

    % Objective state right before the current human decision.
    decisionState.rewardsRemainingBeforeDecision = rewardsRemainingBefore;
    decisionState.humanMovesBeforeDecision = humanMovesBefore;
    decisionState.agentMovesBeforeDecision = agentMovesBefore;
    decisionState.humanRewardsBeforeDecision = humanRewardsBefore;
    decisionState.agentRewardsBeforeDecision = agentRewardsBefore;
    decisionState.previousHumanPosition = previousHumanPosition;
    decisionState.previousHumanStimulusID = previousHumanStimulusID;
    decisionState.previousAgentPosition = previousAgentPosition;
    decisionState.previousAgentStimulusID = previousAgentStimulusID;
    decisionState.isFirstDecisionInEpisode = isFirstDecisionInEpisode;

    % Keep current choice identity for deterministic joins to stimulus facts.
    decisionState.currentHumanPosition = trials.humanPosition;
    decisionState.currentHumanStimulusID = trials.humanStimulusID;
end
