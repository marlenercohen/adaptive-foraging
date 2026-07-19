function state = applyBoardTransition(state, positionID, stimulusID, isRepeat, actor, decisionID, episode)
%af.applyBoardTransition Apply one objective board-state transition.
%   STATE = af.applyBoardTransition(STATE, POSITIONID, STIMULUSID,
%   ISREPEAT, ACTOR, DECISIONID, EPISODE) updates the reconstructed board
%   state using the exact availability transition implemented by the
%   experiment runtime.
%
%   This function contains only board-transition logic. It performs no
%   reward handling, rule evaluation, or behavioral analysis.

    if nargin < 7
        error('af:applyBoardTransition:MissingInput', ...
            'state, positionID, stimulusID, isRepeat, actor, decisionID, and episode are required.');
    end
    if ~isstruct(state)
        error('af:applyBoardTransition:InvalidStateType', 'state must be a struct.');
    end

    requiredFields = {'positionIDs', 'stimulusIDs', 'resolved'};
    missingFields = requiredFields(~isfield(state, requiredFields));
    if ~isempty(missingFields)
        error('af:applyBoardTransition:MissingStateFields', ...
            'state is missing required board field(s): %s', strjoin(missingFields, ', '));
    end

    actor = string(actor);
    if strlength(actor) == 0
        actor = "unknown-actor";
    end

    if isnan(positionID)
        error('af:applyBoardTransition:MissingSelectionPosition', ...
            '%s selection before decisionID %g in episode %g is missing positionID.', ...
            actor, decisionID, episode);
    end
    if positionID < 0 || positionID ~= floor(positionID) || positionID > max(state.positionIDs)
        error('af:applyBoardTransition:OutOfBoundsPosition', ...
            '%s selected invalid positionID %g before decisionID %g in episode %g.', ...
            actor, positionID, decisionID, episode);
    end

    idx = positionID + 1;
    expectedStimulusID = state.stimulusIDs(idx);
    if ~isnan(stimulusID) && expectedStimulusID ~= stimulusID
        error('af:applyBoardTransition:StimulusPositionMismatch', ...
            ['%s selected stimulusID %g at position %g before decisionID %g in ', ...
             'episode %g, but reconstructed board contains stimulusID %g there.'], ...
            actor, stimulusID, positionID, decisionID, episode, expectedStimulusID);
    end

    if isRepeat
        if ~state.resolved(idx)
            error('af:applyBoardTransition:RepeatWasAvailable', ...
                ['%s selection at position %g before decisionID %g in episode %g ', ...
                 'is marked as repeat, but the reconstructed board shows it was still available.'], ...
                actor, positionID, decisionID, episode);
        end
        return;
    end

    if state.resolved(idx)
        error('af:applyBoardTransition:UnavailableSelected', ...
            ['%s selected position %g before decisionID %g in episode %g, but ', ...
             'that position was not available in the reconstructed board.'], ...
            actor, positionID, decisionID, episode);
    end

    % Exact runtime behavior:
    % - js/rule.js returns repeat=true when pos.resolved is already true.
    % - js/app.js sets p.resolved=true for every non-repeat selection.
    % Therefore, repeat selections leave the board unchanged, and every
    % non-repeat selection resolves the selected position.
    state.resolved(idx) = true;
end