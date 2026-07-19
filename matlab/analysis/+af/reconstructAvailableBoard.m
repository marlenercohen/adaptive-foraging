function availableBoard = reconstructAvailableBoard(canonicalState, decisionState)
%af.reconstructAvailableBoard Reconstruct objective pre-decision board availability.
%   AVAILABLEBOARD = af.reconstructAvailableBoard(CANONICALSTATE,
%   DECISIONSTATE) returns one row per available board position immediately
%   before each human decision.
%
%   This function reconstructs board evolution deterministically from:
%   - immutable Layer-1 boardState facts (used to seed each episode and
%     validate reconstruction)
%   - immutable trial facts describing human and agent actions
%   - immutable stimulus metadata
%
%   The output is model-agnostic and contains only objective board state.

    if nargin < 2
        error('af:reconstructAvailableBoard:MissingInput', ...
            'canonicalState and decisionState are required.');
    end
    if ~isstruct(canonicalState) || ~isfield(canonicalState, 'facts')
        error('af:reconstructAvailableBoard:InvalidCanonicalState', ...
            'canonicalState must be a struct returned by af.buildCanonicalState().');
    end
    if ~istable(decisionState)
        error('af:reconstructAvailableBoard:InvalidDecisionStateType', ...
            'decisionState must be a table from af.reconstructDecisionState().');
    end

    requiredFactTables = {'trials', 'stimuli', 'boardState'};
    for i = 1:numel(requiredFactTables)
        if ~isfield(canonicalState.facts, requiredFactTables{i})
            error('af:reconstructAvailableBoard:MissingCanonicalFacts', ...
                'canonicalState.facts.%s is required.', requiredFactTables{i});
        end
    end

    trials = canonicalState.facts.trials;
    stimuli = canonicalState.facts.stimuli;
    boardState = canonicalState.facts.boardState;

    if ~istable(trials) || ~istable(stimuli) || ~istable(boardState)
        error('af:reconstructAvailableBoard:InvalidCanonicalFactType', ...
            'canonicalState facts.trials, facts.stimuli, and facts.boardState must be tables.');
    end

    if isempty(boardState)
        error('af:reconstructAvailableBoard:MissingBoardStateFacts', ...
            ['canonicalState.facts.boardState is empty. Exact objective board ', ...
             'reconstruction requires immutable pre-decision board snapshots ', ...
             'from JSON stateSnapshots to seed each episode.']);
    end

    assertTableVariables(trials, {
        'decisionID','globalDecisionIndex','block','phase','episode', ...
        'humanPosition','humanStimulusID', ...
        'agentPosition','agentStimulusID', ...
        'humanRepeatedOwnLocation','humanRepeatedAgentLocation', ...
        'agentRepeatedOwnLocation','agentRepeatedHumanLocation'
    }, 'af:reconstructAvailableBoard:MissingTrialVariables');

    assertTableVariables(decisionState, {
        'decisionID','globalDecisionIndex','block','phase','episode', ...
        'currentHumanPosition','currentHumanStimulusID', ...
        'previousAgentPosition','previousAgentStimulusID', ...
        'humanRepeatedOwnLocation','humanRepeatedAgentLocation', ...
        'previousAgentRepeatedOwnLocation','previousAgentRepeatedHumanLocation'
    }, 'af:reconstructAvailableBoard:MissingDecisionStateVariables');

    assertTableVariables(boardState, {
        'decisionID','globalDecisionIndex','block','phase','episode', ...
        'positionID','stimulusID','resolved'
    }, 'af:reconstructAvailableBoard:MissingBoardStateVariables');

    assertTableVariables(stimuli, {'stimulusID'}, 'af:reconstructAvailableBoard:MissingStimulusVariables');

    if isempty(decisionState)
        availableBoard = table();
        return;
    end

    decisionKeys = table(double(decisionState.decisionID), double(decisionState.globalDecisionIndex), ...
        'VariableNames', {'decisionID','globalDecisionIndex'});
    trialKeys = table(double(trials.decisionID), double(trials.globalDecisionIndex), ...
        'VariableNames', {'decisionID','globalDecisionIndex'});
    if ~isequaln(decisionKeys, trialKeys)
        error('af:reconstructAvailableBoard:DecisionTrialAlignmentMismatch', ...
            'decisionState rows must align one-to-one with canonical trial facts by decisionID and globalDecisionIndex.');
    end

    ds = decisionState;
    [~, order] = sort(double(ds.globalDecisionIndex));
    ds = ds(order, :);
    trials = trials(order, :);

    rows = repmat(makeAvailableRow(), 0, 1);

    [G, blockValues, phaseValues, episodeValues] = findgroups(trials.block, trials.phase, trials.episode);
    groupIds = unique(G);

    for gi = 1:numel(groupIds)
        idx = find(G == groupIds(gi));
        if isempty(idx)
            continue;
        end

        episodeNumber = double(episodeValues(gi));
        firstDecisionId = double(trials.decisionID(idx(1)));
        seedRows = boardState(double(boardState.decisionID) == firstDecisionId, :);
        if isempty(seedRows)
            error('af:reconstructAvailableBoard:MissingEpisodeSeedSnapshot', ...
                'No boardState seed snapshot found for first decisionID %g in episode %g.', ...
                firstDecisionId, episodeNumber);
        end

        state = seedEpisodeState(seedRows, episodeNumber, firstDecisionId);

        for k = 1:numel(idx)
            i = idx(k);
            currentDecisionId = double(trials.decisionID(i));

            validateCurrentStateAgainstSnapshot(state, boardState, currentDecisionId, episodeNumber);

            % Record every currently available position before the human decision.
            availablePositions = find(~state.resolved);
            if isempty(availablePositions)
                error('af:reconstructAvailableBoard:NoAvailablePositions', ...
                    'No available positions remain before decisionID %g.', currentDecisionId);
            end

            for p = availablePositions(:)'
                row = makeAvailableRow();
                row.decisionID = currentDecisionId;
                row.globalDecisionIndex = double(trials.globalDecisionIndex(i));
                row.block = double(blockValues(gi));
                row.phase = string(phaseValues(gi));
                row.episode = episodeNumber;
                row.actorToMove = "human";
                row.positionID = p;
                row.stimulusID = state.stimulusIDs(p + 1);
                row.available = true;
                rows(end + 1, 1) = row; %#ok<AGROW>
            end

            % Apply the current human action according to protocol rules.
            humanRepeat = logical(trials.humanRepeatedOwnLocation(i)) || logical(trials.humanRepeatedAgentLocation(i));
            state = af.applyBoardTransition(state, ...
                double(trials.humanPosition(i)), ...
                double(trials.humanStimulusID(i)), ...
                humanRepeat, ...
                "human", ...
                currentDecisionId, ...
                episodeNumber);

            % Apply the preceding agent action for the next decision in the episode.
            if k < numel(idx)
                nextIdx = idx(k + 1);
                agentPos = double(ds.previousAgentPosition(nextIdx));
                agentStimulus = double(ds.previousAgentStimulusID(nextIdx));
                if ~isnan(agentPos)
                    agentRepeat = logical(ds.previousAgentRepeatedOwnLocation(nextIdx)) || ...
                        logical(ds.previousAgentRepeatedHumanLocation(nextIdx));
                    state = af.applyBoardTransition(state, ...
                        agentPos, ...
                        agentStimulus, ...
                        agentRepeat, ...
                        "agent", ...
                        double(trials.decisionID(nextIdx)), ...
                        episodeNumber);
                end
            end
        end
    end

    availableBoard = struct2table(rows);
    availableBoard = join(availableBoard, stimuli, 'Keys', 'stimulusID');
    availableBoard = sortrows(availableBoard, {'globalDecisionIndex', 'positionID'});
end

function state = seedEpisodeState(seedRows, episodeNumber, decisionId)
    positionIds = double(seedRows.positionID);
    if any(isnan(positionIds))
        error('af:reconstructAvailableBoard:InvalidSeedPositionID', ...
            'Seed boardState rows contain NaN positionID for episode %g decisionID %g.', ...
            episodeNumber, decisionId);
    end

    maxPosition = max(positionIds);
    expectedPositions = (0:maxPosition)';
    if numel(positionIds) ~= numel(expectedPositions) || ~all(sort(positionIds) == expectedPositions)
        error('af:reconstructAvailableBoard:NonContiguousBoardPositions', ...
            ['Seed boardState for episode %g decisionID %g must contain a ', ...
             'complete contiguous set of positionIDs from 0 to %g.'], ...
            episodeNumber, decisionId, maxPosition);
    end

    state = struct();
    state.positionIDs = expectedPositions;
    state.stimulusIDs = nan(numel(expectedPositions), 1);
    state.resolved = false(numel(expectedPositions), 1);

    for i = 1:height(seedRows)
        pos = double(seedRows.positionID(i));
        state.stimulusIDs(pos + 1) = double(seedRows.stimulusID(i));
        state.resolved(pos + 1) = logical(seedRows.resolved(i));
    end
end

function validateCurrentStateAgainstSnapshot(state, boardState, decisionId, episodeNumber)
    snapshot = boardState(double(boardState.decisionID) == decisionId, :);
    if isempty(snapshot)
        error('af:reconstructAvailableBoard:MissingValidationSnapshot', ...
            'Missing boardState snapshot for decisionID %g in episode %g.', decisionId, episodeNumber);
    end

    pos = double(snapshot.positionID);
    stim = double(snapshot.stimulusID);
    res = logical(snapshot.resolved);

    if numel(pos) ~= numel(state.positionIDs)
        error('af:reconstructAvailableBoard:SnapshotBoardSizeMismatch', ...
            ['boardState snapshot for decisionID %g has %d positions but ', ...
             'reconstructed state has %d.'], ...
            decisionId, numel(pos), numel(state.positionIDs));
    end

    [sortedPos, order] = sort(pos);
    if ~all(sortedPos == state.positionIDs)
        error('af:reconstructAvailableBoard:SnapshotPositionMismatch', ...
            'boardState snapshot positions do not match reconstructed positions for decisionID %g.', decisionId);
    end

    stim = stim(order);
    res = res(order);

    if any(stim ~= state.stimulusIDs)
        bad = find(stim ~= state.stimulusIDs, 1, 'first');
        error('af:reconstructAvailableBoard:StimulusReappearanceMismatch', ...
            ['Reconstructed board stimulusID at decisionID %g position %g is %g ', ...
             'but boardState records %g.'], ...
            decisionId, state.positionIDs(bad), state.stimulusIDs(bad), stim(bad));
    end

    if any(res ~= state.resolved)
        bad = find(res ~= state.resolved, 1, 'first');
        error('af:reconstructAvailableBoard:ResolvedStateMismatch', ...
            ['Reconstructed resolved state at decisionID %g position %g is %d ', ...
             'but boardState records %d.'], ...
            decisionId, state.positionIDs(bad), state.resolved(bad), res(bad));
    end
end

function row = makeAvailableRow()
    row = struct( ...
        'decisionID', NaN, ...
        'globalDecisionIndex', NaN, ...
        'block', NaN, ...
        'phase', "", ...
        'episode', NaN, ...
        'actorToMove', "", ...
        'positionID', NaN, ...
        'stimulusID', NaN, ...
        'available', false ...
    );
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end
