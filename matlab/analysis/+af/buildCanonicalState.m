function canonicalState = buildCanonicalState(trials, stimuli, rules)
%af.buildCanonicalState Build immutable, model-agnostic analysis facts.
%   CANONICALSTATE = af.buildCanonicalState(TRIALS) stores the reconstructed
%   trial-level facts as a stable Layer-1 container.
%
%   CANONICALSTATE = af.buildCanonicalState(TRIALS, STIMULI, RULES) also
%   stores optional stimulus and rule metadata tables when available.
%
%   This function intentionally does not compute behavioral measures.

    if nargin < 1
        error('af:buildCanonicalState:MissingInput', 'trials is required.');
    end
    if nargin < 2
        stimuli = table();
    end
    if nargin < 3
        rules = table();
    end

    if ~istable(trials)
        error('af:buildCanonicalState:InvalidTrialsType', 'trials must be a table.');
    end
    if ~istable(stimuli)
        error('af:buildCanonicalState:InvalidStimuliType', 'stimuli must be a table.');
    end
    if ~istable(rules)
        error('af:buildCanonicalState:InvalidRulesType', 'rules must be a table.');
    end

    requiredVars = {
        'block','phase','episode','trialWithinEpisode','humanSelectionNumber', ...
        'ruleName','ruleType','feature','operator','value','minimumDistance', ...
        'humanStimulusID','humanPosition','humanReward', ...
        'agentStimulusID','agentPosition','agentReward', ...
        'humanRepeatedOwnLocation','humanRepeatedAgentLocation', ...
        'agentRepeatedOwnLocation','agentRepeatedHumanLocation', ...
        'humanEpisodeScore','agentEpisodeScore','rewardsRemaining'
    };
    assertTableVariables(trials, requiredVars, 'af:buildCanonicalState:MissingTrialsVariables');

    facts = trials;
    facts.decisionID = (1:height(facts))';
    facts.globalDecisionIndex = facts.decisionID;

    canonicalState = struct();
    canonicalState.schemaVersion = "af-canonical-1";
    canonicalState.createdAt = datetime('now', 'TimeZone', 'local');
    canonicalState.facts = struct();
    canonicalState.facts.trials = facts;
    canonicalState.facts.stimuli = stimuli;
    canonicalState.facts.rules = rules;
    canonicalState.meta = struct();
    canonicalState.meta.layer = "facts";
    canonicalState.meta.description = "Immutable trial, stimulus, and rule facts for downstream state reconstruction.";
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
