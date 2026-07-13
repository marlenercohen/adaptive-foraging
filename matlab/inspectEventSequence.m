function inspectEventSequence(session, nEvents)
%INSPECTEVENTSEQUENCE Print event log ordering for diagnostics.
%   INSPECTEVENTSEQUENCE(SESSION) prints the first 60 events from
%   SESSION.EVENTLOG (as returned by LOADSESSION), one event per line.
%
%   INSPECTEVENTSEQUENCE(SESSION, NEVENTS) prints the first NEVENTS events.
%
%   This utility is purely diagnostic: it does not interpret behavior,
%   modify SESSION, or compute analyses.

    if nargin < 1
        error('inspectEventSequence:MissingInput', 'session is required.');
    end
    if nargin < 2 || isempty(nEvents)
        nEvents = 60;
    end

    if ~isstruct(session)
        error('inspectEventSequence:InvalidInputType', ...
            'session must be a struct returned by loadSession().');
    end

    if ~(isnumeric(nEvents) || islogical(nEvents)) || ~isscalar(nEvents) || ~isfinite(double(nEvents))
        error('inspectEventSequence:InvalidNEvents', ...
            'nEvents must be a finite numeric scalar.');
    end
    nEvents = floor(double(nEvents));
    if nEvents < 1
        error('inspectEventSequence:InvalidNEvents', ...
            'nEvents must be >= 1.');
    end

    events = afField(session, 'eventLog', struct([]));
    if ~isstruct(events)
        error('inspectEventSequence:InvalidEventLog', ...
            'session.eventLog must be a struct array.');
    end

    totalEvents = numel(events);
    if totalEvents == 0
        fprintf('\n=== Event Sequence (empty) ===\n');
        fprintf('Source: %s\n', char(string(afField(session, 'sourceFile', ""))));
        fprintf('No events found in session.eventLog.\n\n');
        return;
    end

    nToPrint = min(nEvents, totalEvents);

    fprintf('\n=== Event Sequence ===\n');
    fprintf('Source: %s\n', char(string(afField(session, 'sourceFile', ""))));
    fprintf('Showing first %d of %d events (in eventLog order)\n', nToPrint, totalEvents);
    fprintf('%5s | %-22s | %-7s | %-5s | %-5s | %-5s | %-8s | %-6s | %-10s | %-16s\n', ...
        'seq', 'type', 'actor', 'ep', 'move', 'pos', 'stimulus', 'reward', 'rewardValue', 'rewardsRemaining');
    fprintf('%s\n', repmat('-', 1, 122));

    for i = 1:nToPrint
        e = events(i);
        d = afField(e, 'data', struct());
        if ~isstruct(d)
            d = struct();
        end

        seqToken = valueOrNA(afField(e, 'seq', i));
        typeToken = tokenString(afField(e, 'type', ""));

        actorToken = tokenString(afField(d, 'actor', []));
        epToken = valueOrNA(afField(d, 'episodeNumber', []));
        moveToken = valueOrNA(afField(d, 'moveNumber', []));
        posToken = valueOrNA(afField(d, 'positionID', []));
        stimToken = valueOrNA(afField(d, 'stimulusID', []));
        rewardToken = valueOrNA(afField(d, 'reward', []));
        rewardValueToken = valueOrNA(afField(d, 'rewardValue', []));
        rewardsRemainingToken = valueOrNA(afField(d, 'rewardsRemaining', []));

        fprintf('%5s | %-22s | %-7s | %-5s | %-5s | %-5s | %-8s | %-6s | %-10s | %-16s\n', ...
            seqToken, typeToken, actorToken, epToken, moveToken, posToken, ...
            stimToken, rewardToken, rewardValueToken, rewardsRemainingToken);
    end

    fprintf('\n');
end

function out = valueOrNA(value)
    if isempty(value)
        out = 'NA';
        return;
    end

    if isstring(value)
        if isempty(value)
            out = 'NA';
        else
            out = char(value(1));
        end
        return;
    end

    if ischar(value)
        if isempty(value)
            out = 'NA';
        else
            out = value;
        end
        return;
    end

    if islogical(value)
        out = char(string(logical(value(1))));
        return;
    end

    if isnumeric(value)
        if isempty(value)
            out = 'NA';
        else
            out = num2str(value(1));
        end
        return;
    end

    if iscell(value)
        if isempty(value)
            out = 'NA';
        else
            out = '<cell>';
        end
        return;
    end

    if isstruct(value)
        out = '<struct>';
        return;
    end

    try
        out = char(string(value));
    catch
        out = '<unprintable>';
    end
end

function out = tokenString(value)
    out = valueOrNA(value);
    if strcmp(out, 'NA')
        out = '-';
    end
end
