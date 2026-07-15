function trials = loadSessionCSV(filename, stimuli, rules)
%LOADSESSIONCSV Build trial table directly from Gorilla behavioral CSV.
%   TRIALS = LOADSESSIONCSV(FILENAME, STIMULI, RULES) reads a Gorilla
%   behavioral export CSV (reference format: data-task-qwcj.csv), converts
%   behavioral rows into a normalized event stream, and delegates trial
%   reconstruction to BUILDTRIALTABLE.
%
%   This importer matches CSV columns by name (not order) and ignores
%   non-behavioral rows except where metadata is useful.
%
%   Notes:
%   - Gorilla CSV does not provide explicit score_update/reward_delivered
%     event rows in this format. These are synthesized from move rows.
%   - Reward reconstruction assumes:
%       * "Reward" indicates whether the current move earned reward.
%       * "Rewards Remaining" is reported AFTER the current move outcome.
%     This assumption is validated where possible and warning(s) are
%     emitted when inconsistencies are detected.
%   - buildTrialTable remains the reference implementation of behavioral
%     logic and derived variable computation.

    if nargin < 3
        error('loadSessionCSV:MissingInput', 'filename, stimuli, and rules are required.');
    end

    if ~(ischar(filename) || isstring(filename))
        error('loadSessionCSV:InvalidFilenameType', 'filename must be char or string.');
    end

    filename = char(filename);
    if ~isfile(filename)
        error('loadSessionCSV:FileNotFound', 'File not found: %s', filename);
    end

    opts = detectImportOptions(filename, 'FileType', 'text');
    opts.VariableNamingRule = 'preserve';
    data = readtable(filename, opts);

    requiredColumns = {
        'Event Type', ...
        'Event Index', ...
        'Block Number', ...
        'Phase Name', ...
        'Rule File', ...
        'Episode Number', ...
        'Move Number', ...
        'Actor', ...
        'Position ID', ...
        'Stimulus ID', ...
        'Reward', ...
        'Repeat', ...
        'Human Score', ...
        'Agent Score', ...
        'Human Total Score', ...
        'Agent Total Score', ...
        'Rewards Remaining'
    };
    assertColumns(data, requiredColumns);

    % Sort by explicit event index if present.
    eventIndex = toNumberColumn(data.('Event Index'));
    if any(~isnan(eventIndex))
        [~, order] = sortrows([replaceNaN(eventIndex, inf), (1:height(data))']);
        data = data(order, :);
    end

    eventType = lower(strtrim(string(data.('Event Type'))));
    moveMask = eventType == "human_move" | eventType == "agent_move";
    moveRows = data(moveMask, :);

    if isempty(moveRows)
        session = struct('sourceFile', filename, 'eventLog', struct([]));
        trials = buildTrialTable(session, stimuli, rules);
        return;
    end

    eventLog = struct([]);
    sequence = 0;

    currentEpisode = NaN;
    previousEpisodeRule = "";
    warnRewardAssumption();

    for i = 1:height(moveRows)
        row = moveRows(i, :);

        rowEpisode = toScalar(row.('Episode Number'));
        rowRule = asStringCell(row.('Rule File'));
        rowPhase = asStringCell(row.('Phase Name'));
        rowBlock = toScalar(row.('Block Number'));
        rowMove = toScalar(row.('Move Number'));
        rowActor = lower(asStringCell(row.('Actor')));
        rowPosition = toScalar(row.('Position ID'));
        rowStimulus = toScalar(row.('Stimulus ID'));
        rowReward = toBoolean(row.('Reward'));
        rowRepeat = toBoolean(row.('Repeat'));
        rowHumanScore = toScalar(row.('Human Score'));
        rowAgentScore = toScalar(row.('Agent Score'));
        rowHumanTotal = toScalar(row.('Human Total Score'));
        rowAgentTotal = toScalar(row.('Agent Total Score'));
        rowRewardsRemaining = toScalar(row.('Rewards Remaining'));

        if isnan(rowEpisode)
            error('loadSessionCSV:MissingEpisodeNumber', ...
                'Behavioral move row %d is missing Episode Number.', i);
        end
        if isnan(rowMove)
            error('loadSessionCSV:MissingMoveNumber', ...
                'Behavioral move row %d is missing Move Number.', i);
        end
        if strlength(rowActor) == 0
            error('loadSessionCSV:MissingActor', ...
                'Behavioral move row %d is missing Actor.', i);
        end
        if isnan(rowPosition)
            error('loadSessionCSV:MissingPositionID', ...
                'Behavioral move row %d is missing Position ID.', i);
        end
        if isnan(rowStimulus)
            error('loadSessionCSV:MissingStimulusID', ...
                'Behavioral move row %d is missing Stimulus ID.', i);
        end

        % Start a new episode whenever the episode number changes.
        isNewEpisode = isnan(currentEpisode) || ~isequal(rowEpisode, currentEpisode);
        if isNewEpisode
            % ASSUMPTION: Gorilla "Rewards Remaining" is post-move. To
            % derive pre-move episode capacity for episode_start, add the
            % current move reward (0/1) back to post-move remaining.
            rewardsAvailable = rowRewardsRemaining + double(rowReward);
            if isnan(rewardsAvailable)
                rewardsAvailable = rowRewardsRemaining;
            end

            sequence = sequence + 1;
            eventLog(end + 1) = makeEvent(sequence, 'episode_start', struct( ...
                'blockNumber', rowBlock, ...
                'phaseName', char(rowPhase), ...
                'episodeNumber', rowEpisode, ...
                'ruleFile', char(rowRule), ...
                'rewardsAvailable', rewardsAvailable, ...
                'maxSelections', NaN)); %#ok<AGROW>

            if ~isnan(currentEpisode) && strlength(previousEpisodeRule) > 0 && strlength(rowRule) > 0 && previousEpisodeRule ~= rowRule
                sequence = sequence + 1;
                eventLog(end + 1) = makeEvent(sequence, 'rule_change', struct( ...
                    'episodeNumber', rowEpisode, ...
                    'fromRuleFile', char(previousEpisodeRule), ...
                    'toRuleFile', char(rowRule))); %#ok<AGROW>
            end

            currentEpisode = rowEpisode;
            previousEpisodeRule = rowRule;
        end

        validateRewardConsistency(rowRewardsRemaining, currentEpisode, rowMove, rowActor);

        % Optional consistency event used by buildTrialTable checks.
        sequence = sequence + 1;
        eventLog(end + 1) = makeEvent(sequence, 'stimulus_selection', struct( ...
            'actor', char(rowActor), ...
            'blockNumber', rowBlock, ...
            'episodeNumber', rowEpisode, ...
            'moveNumber', rowMove, ...
            'positionID', rowPosition, ...
            'stimulusID', rowStimulus, ...
            'repeated', rowRepeat)); %#ok<AGROW>

        if rowRepeat
            sequence = sequence + 1;
            eventLog(end + 1) = makeEvent(sequence, 'repeated_stimulus_selection', struct( ...
                'actor', char(rowActor), ...
                'blockNumber', rowBlock, ...
                'episodeNumber', rowEpisode, ...
                'moveNumber', rowMove, ...
                'positionID', rowPosition, ...
                'stimulusID', rowStimulus)); %#ok<AGROW>
        end

        moveType = 'human_move';
        if rowActor == "agent"
            moveType = 'agent_move';
        elseif rowActor ~= "human"
            error('loadSessionCSV:UnsupportedActor', ...
                'Unsupported Actor value "%s" at move row %d.', rowActor, i);
        end

        sequence = sequence + 1;
        eventLog(end + 1) = makeEvent(sequence, moveType, struct( ...
            'actor', char(rowActor), ...
            'blockNumber', rowBlock, ...
            'phaseName', char(rowPhase), ...
            'ruleFile', char(rowRule), ...
            'episodeNumber', rowEpisode, ...
            'moveNumber', rowMove, ...
            'positionID', rowPosition, ...
            'stimulusID', rowStimulus, ...
            'reward', rowReward, ...
            'repeat', rowRepeat)); %#ok<AGROW>

        if rowReward
            sequence = sequence + 1;
            eventLog(end + 1) = makeEvent(sequence, 'reward_delivered', struct( ...
                'actor', char(rowActor), ...
                'blockNumber', rowBlock, ...
                'episodeNumber', rowEpisode, ...
                'moveNumber', rowMove, ...
                'positionID', rowPosition, ...
                'stimulusID', rowStimulus, ...
                'rewardValue', 1, ...
                'rewardsRemaining', rowRewardsRemaining)); %#ok<AGROW>
        end

        sequence = sequence + 1;
        eventLog(end + 1) = makeEvent(sequence, 'score_update', struct( ...
            'blockNumber', rowBlock, ...
            'episodeNumber', rowEpisode, ...
            'moveNumber', rowMove, ...
            'humanScore', rowHumanScore, ...
            'agentScore', rowAgentScore, ...
            'humanTotalScore', rowHumanTotal, ...
            'agentTotalScore', rowAgentTotal, ...
            'rewardsRemaining', rowRewardsRemaining)); %#ok<AGROW>

    end

    session = struct();
    session.sourceFile = filename;
    session.schemaVersion = "gorilla-csv-1";
    session.sessionMetadata = struct();
    session.eventLog = eventLog;
    session.stateSnapshots = struct([]);
    session.internalErrors = struct([]);
    session.raw = struct();

    trials = buildTrialTable(session, stimuli, rules);
end

function assertColumns(tbl, requiredColumns)
    missing = requiredColumns(~ismember(requiredColumns, tbl.Properties.VariableNames));
    if ~isempty(missing)
        error('loadSessionCSV:MissingColumns', ...
            'CSV is missing required column(s): %s', strjoin(missing, ', '));
    end
end

function ev = makeEvent(seq, typeName, data)
    ev = struct('seq', seq, 'ts', "", 'type', char(typeName), 'data', data);
end

function value = toScalar(raw)
    if iscell(raw)
        raw = raw{1};
    end

    if isstring(raw)
        raw = string(raw);
        if numel(raw) > 1
            raw = raw(1);
        end
        raw = strtrim(raw);
        if strlength(raw) == 0
            value = NaN;
            return;
        end
        n = str2double(raw);
        if isnan(n)
            value = NaN;
        else
            value = n;
        end
        return;
    end

    if ischar(raw)
        s = strtrim(string(raw));
        if strlength(s) == 0
            value = NaN;
            return;
        end
        n = str2double(s);
        if isnan(n)
            value = NaN;
        else
            value = n;
        end
        return;
    end

    if isnumeric(raw) || islogical(raw)
        if isempty(raw)
            value = NaN;
        else
            value = double(raw(1));
        end
        return;
    end

    value = NaN;
end

function out = asStringCell(raw)
    if iscell(raw)
        raw = raw{1};
    end
    if isstring(raw)
        out = strtrim(string(raw(1)));
        return;
    end
    if ischar(raw)
        out = strtrim(string(raw));
        return;
    end
    out = "";
end

function tf = toBoolean(raw)
    if iscell(raw)
        raw = raw{1};
    end

    if islogical(raw)
        tf = logical(raw(1));
        return;
    end

    if isnumeric(raw)
        if isempty(raw)
            tf = false;
        else
            tf = raw(1) ~= 0;
        end
        return;
    end

    s = lower(strtrim(string(raw)));
    if s == "" || s == "nan"
        tf = false;
        return;
    end

    tf = any(strcmp(s, ["1","true","yes","y"]));
end

function out = toNumberColumn(col)
    out = nan(size(col, 1), 1);
    for i = 1:numel(out)
        out(i) = toScalar(col(i));
    end
end

function x = replaceNaN(x, replacement)
    x(isnan(x)) = replacement;
end

function warnRewardAssumption()
    persistent didWarn;
    if isempty(didWarn) || ~didWarn
        warning('loadSessionCSV:RewardAssumption', ...
            ['Reward reconstruction assumes Gorilla CSV reports ', ...
             '"Rewards Remaining" after the move and "Reward" indicates ', ...
             'whether the move earned reward.']);
        didWarn = true;
    end
end

function validateRewardConsistency(rowRemaining, episodeNumber, moveNumber, actor)
    if ~isnan(rowRemaining) && rowRemaining < 0
        warning('loadSessionCSV:NegativeRewardsRemaining', ...
            'Negative Rewards Remaining at episode %g move %g (%s).', episodeNumber, moveNumber, char(actor));
    end
end
