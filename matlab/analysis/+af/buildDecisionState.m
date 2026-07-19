function [decisionState, canonicalState] = buildDecisionState(trials, stimuli, rules)
%af.buildDecisionState Minimal Layer-1 -> Layer-2 pipeline entry point.
%   [DECISIONSTATE, CANONICALSTATE] = af.buildDecisionState(TRIALS)
%   constructs immutable facts and then reconstructs objective pre-decision
%   state for each human choice.
%
%   [DECISIONSTATE, CANONICALSTATE] = af.buildDecisionState(TRIALS, STIMULI,
%   RULES) includes optional metadata tables in Layer 1.

    if nargin < 1
        error('af:buildDecisionState:MissingInput', 'trials is required.');
    end
    if nargin < 2
        stimuli = table();
    end
    if nargin < 3
        rules = table();
    end

    canonicalState = af.buildCanonicalState(trials, stimuli, rules);
    decisionState = af.reconstructDecisionState(canonicalState);
end
