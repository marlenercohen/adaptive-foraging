function stimulusDifficulty = computeStimulusDifficulty(decisionState, stimulusMetadata)
%af.computeStimulusDifficulty Descriptive per-stimulus interaction summary.
%   STIMULUSDIFFICULTY = af.computeStimulusDifficulty(DECISIONSTATE,
%   STIMULUSMETADATA) returns one row per stimulus with descriptive counts
%   and rates from human/agent interactions.
%
%   This module is intentionally model-agnostic. It does not estimate
%   evidence, beliefs, latent values, learning rates, or uncertainty.

    if nargin < 2
        error('af:computeStimulusDifficulty:MissingInput', ...
            'decisionState and stimulusMetadata are required.');
    end
    if ~istable(decisionState)
        error('af:computeStimulusDifficulty:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end
    if ~istable(stimulusMetadata)
        error('af:computeStimulusDifficulty:InvalidStimulusMetadataType', ...
            'stimulusMetadata must be a table.');
    end

    requiredStimulusVars = {'stimulusID'};
    assertTableVariables(stimulusMetadata, requiredStimulusVars, ...
        'af:computeStimulusDifficulty:MissingStimulusMetadataVariables');

    % Required Layer-2 fields for this descriptive module.
    requiredDecisionVars = {
        'episode', ...
        'currentHumanStimulusID', ...
        'currentHumanReward', ...
        'humanRepeatedOwnLocation', ...
        'humanRepeatedAgentLocation', ...
        'previousAgentStimulusID', ...
        'previousAgentReward', ...
        'previousAgentRepeatedOwnLocation', ...
        'previousAgentRepeatedHumanLocation'
    };

    missingDecisionVars = requiredDecisionVars(~ismember(requiredDecisionVars, decisionState.Properties.VariableNames));
    if ~isempty(missingDecisionVars)
        error('af:computeStimulusDifficulty:MissingDecisionStateVariables', ...
            ['decisionState is missing required Layer-2 field(s): %s. ', ...
             'Add these fields in af.reconstructDecisionState, sourced from Layer-1 trials facts.'], ...
            strjoin(missingDecisionVars, ', '));
    end

    if isempty(stimulusMetadata)
        stimulusDifficulty = table();
        return;
    end

    ids = double(stimulusMetadata.stimulusID);
    nStim = numel(ids);

    nHumanSelections = zeros(nStim, 1);
    nHumanRewards = zeros(nStim, 1);
    nAgentSelections = zeros(nStim, 1);
    nAgentRewards = zeros(nStim, 1);
    nHumanRepeatSelections = zeros(nStim, 1);
    nAgentRepeatSelections = zeros(nStim, 1);
    nEpisodesWithHumanSelection = zeros(nStim, 1);
    nEpisodesWithAgentSelection = zeros(nStim, 1);

    humanStim = double(decisionState.currentHumanStimulusID);
    humanReward = logical(decisionState.currentHumanReward);
    humanRepeat = logical(decisionState.humanRepeatedOwnLocation) | logical(decisionState.humanRepeatedAgentLocation);

    agentStim = double(decisionState.previousAgentStimulusID);
    agentReward = logical(decisionState.previousAgentReward);
    agentRepeat = logical(decisionState.previousAgentRepeatedOwnLocation) | logical(decisionState.previousAgentRepeatedHumanLocation);

    episodes = double(decisionState.episode);

    for i = 1:nStim
        sid = ids(i);

        humanMask = ~isnan(humanStim) & (humanStim == sid);
        agentMask = ~isnan(agentStim) & (agentStim == sid);

        nHumanSelections(i) = sum(humanMask);
        nHumanRewards(i) = sum(humanReward(humanMask));
        nAgentSelections(i) = sum(agentMask);
        nAgentRewards(i) = sum(agentReward(agentMask));

        nHumanRepeatSelections(i) = sum(humanRepeat(humanMask));
        nAgentRepeatSelections(i) = sum(agentRepeat(agentMask));

        nEpisodesWithHumanSelection(i) = numel(unique(episodes(humanMask)));
        nEpisodesWithAgentSelection(i) = numel(unique(episodes(agentMask)));
    end

    stimulusDifficulty = stimulusMetadata;
    stimulusDifficulty.nHumanSelections = nHumanSelections;
    stimulusDifficulty.nHumanRewards = nHumanRewards;
    stimulusDifficulty.humanRewardRate = safeDivide(nHumanRewards, nHumanSelections);

    stimulusDifficulty.nAgentSelections = nAgentSelections;
    stimulusDifficulty.nAgentRewards = nAgentRewards;
    stimulusDifficulty.agentRewardRate = safeDivide(nAgentRewards, nAgentSelections);

    stimulusDifficulty.nHumanRepeatSelections = nHumanRepeatSelections;
    stimulusDifficulty.nAgentRepeatSelections = nAgentRepeatSelections;
    stimulusDifficulty.nTotalRepeatSelections = nHumanRepeatSelections + nAgentRepeatSelections;

    stimulusDifficulty.nEpisodesWithHumanSelection = nEpisodesWithHumanSelection;
    stimulusDifficulty.nEpisodesWithAgentSelection = nEpisodesWithAgentSelection;
    stimulusDifficulty.nEpisodesWithAnySelection = max(nEpisodesWithHumanSelection, nEpisodesWithAgentSelection);

    stimulusDifficulty.nTotalSelections = nHumanSelections + nAgentSelections;
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end

function out = safeDivide(num, den)
    out = nan(size(num));
    nonzero = den ~= 0;
    out(nonzero) = num(nonzero) ./ den(nonzero);
end
