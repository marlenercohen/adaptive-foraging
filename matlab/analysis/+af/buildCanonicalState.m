function canonicalState = buildCanonicalState(trials, stimuli, rules, session)
%af.buildCanonicalState Build immutable, model-agnostic analysis facts.
%   CANONICALSTATE = af.buildCanonicalState(TRIALS) stores the reconstructed
%   trial-level facts as a stable Layer-1 container.
%
%   CANONICALSTATE = af.buildCanonicalState(TRIALS, STIMULI, RULES) also
%   stores optional stimulus and rule metadata tables when available.
%
%   CANONICALSTATE = af.buildCanonicalState(TRIALS, STIMULI, RULES, SESSION)
%   additionally materializes immutable board-state facts from JSON
%   stateSnapshots when available.
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
    if nargin < 4
        session = struct();
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
    if ~isstruct(session)
        error('af:buildCanonicalState:InvalidSessionType', 'session must be a struct when provided.');
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

    boardState = buildBoardStateFacts(facts, stimuli, session);

    canonicalState = struct();
    canonicalState.schemaVersion = "af-canonical-2";
    canonicalState.createdAt = datetime('now', 'TimeZone', 'local');
    canonicalState.facts = struct();
    canonicalState.facts.trials = facts;
    canonicalState.facts.stimuli = stimuli;
    canonicalState.facts.rules = rules;
    canonicalState.facts.boardState = boardState;
    canonicalState.meta = struct();
    canonicalState.meta.layer = "facts";
    canonicalState.meta.description = [ ...
        "Immutable trial, stimulus, rule, and board-state facts for downstream state reconstruction.", ...
        "boardState is a Layer-1 fact table derived directly from JSON stateSnapshots." ...
    ];
end

function assertTableVariables(tbl, requiredVars, errorId)
    missing = requiredVars(~ismember(requiredVars, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error(errorId, 'Missing required table variable(s): %s', strjoin(missing, ', '));
    end
end

function boardState = buildBoardStateFacts(trials, stimuli, session)
    boardState = emptyBoardStateTable();

    snapshots = getStructArrayField(session, 'stateSnapshots');
    if isempty(snapshots)
        return;
    end

    if isempty(stimuli)
        error('af:buildCanonicalState:MissingStimuliForBoardState', ...
            ['stimulus metadata is required to validate boardState stimulus IDs ', ...
             'when session.stateSnapshots are provided.']);
    end
    assertTableVariables(stimuli, {'stimulusID'}, 'af:buildCanonicalState:MissingStimulusIDVariable');

    stimulusIds = double(stimuli.stimulusID);

    [G, blockValues, phaseValues, episodeValues] = findgroups(trials.block, trials.phase, trials.episode);
    groupIds = unique(G);

    rows = repmat(makeBoardStateRow(), 0, 1);
    expectedBoardSize = NaN;
    snapshotCounter = 0;

    for gi = 1:numel(groupIds)
        rowIdx = find(G == groupIds(gi));
        episodeNumber = double(episodeValues(gi));
        preDecisionSnapshots = selectPreDecisionSnapshots(snapshots, episodeNumber);

        if numel(preDecisionSnapshots) ~= numel(rowIdx)
            error('af:buildCanonicalState:SnapshotDecisionCountMismatch', ...
                ['Episode %g has %d human decisions in trials but %d pre-decision ', ...
                 'board snapshots in session.stateSnapshots.'], ...
                episodeNumber, numel(rowIdx), numel(preDecisionSnapshots));
        end

        for k = 1:numel(rowIdx)
            trialRow = rowIdx(k);
            snapshot = preDecisionSnapshots(k);
            locations = getSnapshotLocations(snapshot, episodeNumber);
            snapshotCounter = snapshotCounter + 1;

            positionIds = nan(numel(locations), 1);
            for j = 1:numel(locations)
                loc = locations(j);
                positionIds(j) = getNumericField(loc, 'positionID', NaN);
            end

            if any(isnan(positionIds))
                error('af:buildCanonicalState:MissingSnapshotPositionID', ...
                    'Snapshot %d for episode %g contains a location with missing positionID.', ...
                    snapshotCounter, episodeNumber);
            end
            if numel(unique(positionIds)) ~= numel(positionIds)
                error('af:buildCanonicalState:DuplicateSnapshotPosition', ...
                    'Snapshot %d for episode %g contains duplicate positionIDs.', ...
                    snapshotCounter, episodeNumber);
            end

            if isnan(expectedBoardSize)
                expectedBoardSize = numel(locations);
            elseif numel(locations) ~= expectedBoardSize
                error('af:buildCanonicalState:InconsistentBoardSize', ...
                    ['Snapshot %d contains %d positions, but earlier snapshots in ', ...
                     'this session contained %d.'], ...
                    snapshotCounter, numel(locations), expectedBoardSize);
            end

            for j = 1:numel(locations)
                loc = locations(j);
                stimulusId = getSnapshotStimulusID(loc, episodeNumber, snapshotCounter);
                if ~ismember(stimulusId, stimulusIds)
                    error('af:buildCanonicalState:UnknownBoardStateStimulusID', ...
                        ['Snapshot %d for episode %g references stimulusID %g, ', ...
                         'which is missing from the stimuli table.'], ...
                        snapshotCounter, episodeNumber, stimulusId);
                end

                resolved = getResolvedFlag(loc, episodeNumber, snapshotCounter);
                imageInstance = getStructField(loc, 'imageInstance', struct());

                row = makeBoardStateRow();
                row.decisionID = double(trials.decisionID(trialRow));
                row.globalDecisionIndex = double(trials.globalDecisionIndex(trialRow));
                row.block = double(blockValues(gi));
                row.phase = string(phaseValues(gi));
                row.episode = episodeNumber;
                row.snapshotIndex = snapshotCounter;
                row.snapshotSeq = getNumericField(snapshot, 'seq', NaN);
                row.snapshotReason = string(getNestedString(snapshot, {'meta', 'reason'}));
                row.snapshotActor = string(getNestedString(snapshot, {'meta', 'actor'}));
                row.positionID = double(getNumericField(loc, 'positionID', NaN));
                row.stimulusID = stimulusId;
                row.resolved = resolved;
                row.imageLabel = string(getStringField(imageInstance, 'label', ""));
                row.imageSrc = string(getStringField(imageInstance, 'imageSrc', ""));

                rows(end + 1, 1) = row; %#ok<AGROW>
            end
        end
    end

    boardState = struct2table(rows);

    decisionIds = double(trials.decisionID);
    boardDecisionIds = unique(double(boardState.decisionID));
    if numel(boardDecisionIds) ~= numel(decisionIds) || ~all(boardDecisionIds(:) == decisionIds(:))
        error('af:buildCanonicalState:MissingBoardSnapshotForDecision', ...
            'Every human decision must have exactly one corresponding pre-decision board snapshot.');
    end
end

function preSnapshots = selectPreDecisionSnapshots(snapshots, episodeNumber)
    keep = false(numel(snapshots), 1);
    for i = 1:numel(snapshots)
        snapEpisode = getNestedNumeric(snapshots(i), {'meta', 'episodeNumber'}, NaN);
        if isnan(snapEpisode) || snapEpisode ~= episodeNumber
            continue;
        end

        reason = string(getNestedString(snapshots(i), {'meta', 'reason'}));
        actor = string(getNestedString(snapshots(i), {'meta', 'actor'}));
        keep(i) = (reason == "episode_start") || (reason == "post_move" && actor == "agent");
    end
    preSnapshots = snapshots(keep);
end

function locations = getSnapshotLocations(snapshot, episodeNumber)
    state = getStructField(snapshot, 'state', struct());
    locations = getStructArrayField(state, 'stimulusLocations');
    if isempty(locations)
        error('af:buildCanonicalState:MissingStimulusLocations', ...
            'Snapshot for episode %g is missing state.stimulusLocations.', episodeNumber);
    end
end

function stimulusId = getSnapshotStimulusID(location, episodeNumber, snapshotIndex)
    imageInstance = getStructField(location, 'imageInstance', struct());
    stimulusId = getNumericField(imageInstance, 'id', NaN);
    if isnan(stimulusId)
        error('af:buildCanonicalState:MissingSnapshotStimulusID', ...
            ['Snapshot %d for episode %g contains a board position with ', ...
             'missing imageInstance.id.'], ...
            snapshotIndex, episodeNumber);
    end
end

function resolved = getResolvedFlag(location, episodeNumber, snapshotIndex)
    if ~isfield(location, 'resolved')
        error('af:buildCanonicalState:MissingResolvedFlag', ...
            'Snapshot %d for episode %g is missing location.resolved.', ...
            snapshotIndex, episodeNumber);
    end

    raw = location.resolved;
    if islogical(raw)
        if isempty(raw)
            error('af:buildCanonicalState:InvalidResolvedFlag', ...
                'Snapshot %d for episode %g has empty logical resolved value.', ...
                snapshotIndex, episodeNumber);
        end
        resolved = logical(raw(1));
        return;
    end

    error('af:buildCanonicalState:NonLogicalResolvedFlag', ...
        'Snapshot %d for episode %g has non-logical resolved value of type %s.', ...
        snapshotIndex, episodeNumber, class(raw));
end

function row = makeBoardStateRow()
    row = struct( ...
        'decisionID', NaN, ...
        'globalDecisionIndex', NaN, ...
        'block', NaN, ...
        'phase', "", ...
        'episode', NaN, ...
        'snapshotIndex', NaN, ...
        'snapshotSeq', NaN, ...
        'snapshotReason', "", ...
        'snapshotActor', "", ...
        'positionID', NaN, ...
        'stimulusID', NaN, ...
        'resolved', false, ...
        'imageLabel', "", ...
        'imageSrc', "" ...
    );
end

function tbl = emptyBoardStateTable()
    tbl = struct2table(repmat(makeBoardStateRow(), 0, 1));
end

function out = getStructField(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName)
        out = s.(fieldName);
    else
        out = defaultValue;
    end
end

function out = getStructArrayField(s, fieldName)
    out = struct([]);
    if isstruct(s) && isfield(s, fieldName)
        candidate = s.(fieldName);
        if isstruct(candidate)
            out = candidate;
        end
    end
end

function value = getNumericField(s, fieldName, defaultValue)
    value = defaultValue;
    if ~isstruct(s) || ~isfield(s, fieldName)
        return;
    end

    raw = s.(fieldName);
    if isnumeric(raw) || islogical(raw)
        if ~isempty(raw)
            value = double(raw(1));
        end
        return;
    end

    if isstring(raw) || ischar(raw)
        parsed = str2double(string(raw));
        if ~isnan(parsed)
            value = parsed;
        end
    end
end

function value = getNestedNumeric(s, path, defaultValue)
    current = s;
    for i = 1:numel(path)
        if ~isstruct(current) || ~isfield(current, path{i})
            value = defaultValue;
            return;
        end
        current = current.(path{i});
    end
    if isnumeric(current) || islogical(current)
        if isempty(current)
            value = defaultValue;
        else
            value = double(current(1));
        end
        return;
    end
    if isstring(current) || ischar(current)
        parsed = str2double(string(current));
        if isnan(parsed)
            value = defaultValue;
        else
            value = parsed;
        end
        return;
    end
    value = defaultValue;
end

function value = getNestedString(s, path)
    current = s;
    for i = 1:numel(path)
        if ~isstruct(current) || ~isfield(current, path{i})
            value = "";
            return;
        end
        current = current.(path{i});
    end
    value = getStringField(struct('value', current), 'value', "");
end

function value = getStringField(s, fieldName, defaultValue)
    value = defaultValue;
    if ~isstruct(s) || ~isfield(s, fieldName)
        return;
    end

    raw = s.(fieldName);
    if isstring(raw)
        if isempty(raw)
            value = defaultValue;
        else
            value = string(raw(1));
        end
        return;
    end
    if ischar(raw)
        value = string(raw);
        return;
    end
    if isnumeric(raw) || islogical(raw)
        if isempty(raw)
            value = defaultValue;
        else
            value = string(raw(1));
        end
    end
end
