function [decisionState, canonicalState] = buildDecisionState(trials, stimuli, rules, session)
%af.buildDecisionState Minimal Layer-1 -> Layer-2 pipeline entry point.
%   [DECISIONSTATE, CANONICALSTATE] = af.buildDecisionState(TRIALS)
%   constructs immutable facts and then reconstructs objective pre-decision
%   state for each human choice.
%
%   [DECISIONSTATE, CANONICALSTATE] = af.buildDecisionState(TRIALS, STIMULI,
%   RULES) includes optional metadata tables in Layer 1.
%
%   [DECISIONSTATE, CANONICALSTATE] = af.buildDecisionState(TRIALS, STIMULI,
%   RULES, SESSION) additionally materializes immutable board-state facts
%   from JSON session.stateSnapshots when available.

    if nargin < 1
        error('af:buildDecisionState:MissingInput', 'trials is required.');
    end
    if nargin < 2
        stimuli = table();
    end
    if nargin < 3
        rules = table();
    end
    if nargin < 4
        session = struct();
    end

    canonicalState = af.buildCanonicalState(trials, stimuli, rules, session);
    decisionState = af.reconstructDecisionState(canonicalState);
end
