function report = summarizeEventLog(session)
%SUMMARIZEEVENTLOG Print a structural summary of session.eventLog.
%   REPORT = SUMMARIZEEVENTLOG(SESSION) inspects SESSION.EVENTLOG (as
%   returned by LOADSESSION) and prints a human-readable schema summary.
%   It reports:
%     - Unique event types and occurrence counts
%     - Top-level event fields observed across all events
%     - For each event type:
%         * union of all event.data fields observed
%         * representative example value for each field
%         * whether each field is sometimes missing
%
%   This function is diagnostic only and does not modify SESSION.

    if nargin < 1
        error('summarizeEventLog:MissingInput', 'session is required.');
    end
    if ~isstruct(session)
        error('summarizeEventLog:InvalidInputType', ...
            'session must be a struct returned by loadSession().');
    end

    events = afField(session, 'eventLog', struct([]));
    if ~isstruct(events)
        error('summarizeEventLog:InvalidEventLog', ...
            'session.eventLog must be a struct array.');
    end

    report = struct();
    report.sourceFile = afField(session, 'sourceFile', "");
    report.totalEvents = numel(events);
    report.topLevelFields = struct([]);
    report.eventTypes = struct([]);

    fprintf('\n=== Event Log Schema Summary ===\n');
    fprintf('Source: %s\n', char(string(report.sourceFile)));
    fprintf('Total events: %d\n', report.totalEvents);

    if isempty(events)
        fprintf('eventLog is empty.\n\n');
        return;
    end

    % Top-level fields across all events.
    [topFieldNames, topFieldPresentCounts, topFieldExamples] = collectTopLevelFieldStats(events);

    report.topLevelFields = struct( ...
        'name', cellstr(topFieldNames), ...
        'presentCount', num2cell(topFieldPresentCounts), ...
        'example', topFieldExamples ...
    );

    fprintf('\nTop-level event fields (outside event.data):\n');
    for i = 1:numel(topFieldNames)
        fprintf('  - %s (present in %d/%d)\n', ...
            topFieldNames(i), topFieldPresentCounts(i), numel(events));
        fprintf('      example: %s\n', formatValue(topFieldExamples{i}));
    end

    eventTypes = strings(numel(events), 1);
    for i = 1:numel(events)
        eventTypes(i) = string(afField(events(i), 'type', ""));
    end

    uniqueTypes = unique(eventTypes, 'stable');

    fprintf('\nUnique event types: %d\n', numel(uniqueTypes));

    typeReports = repmat(struct( ...
        'type', "", ...
        'count', 0, ...
        'dataFields', struct([]) ...
    ), numel(uniqueTypes), 1);

    for t = 1:numel(uniqueTypes)
        typeName = uniqueTypes(t);
        idx = find(eventTypes == typeName);
        typeEvents = events(idx);
        typeCount = numel(typeEvents);

        fprintf('\n----------------------------------------\n');
        fprintf('Type: %s\n', typeName);
        fprintf('Count: %d\n', typeCount);

        [fieldNames, presentCounts, fieldExamples] = collectDataFieldStats(typeEvents);

        if isempty(fieldNames)
            fprintf('event.data fields: (none observed)\n');
            typeReports(t).type = typeName;
            typeReports(t).count = typeCount;
            typeReports(t).dataFields = struct([]);
            continue;
        end

        fprintf('event.data fields (union across all "%s" events):\n', typeName);

        fieldReports = repmat(struct( ...
            'name', "", ...
            'presentCount', 0, ...
            'missingCount', 0, ...
            'sometimesMissing', false, ...
            'example', [] ...
        ), numel(fieldNames), 1);

        for f = 1:numel(fieldNames)
            missingCount = typeCount - presentCounts(f);
            sometimesMissing = missingCount > 0;

            statusText = 'always present';
            if sometimesMissing
                statusText = sprintf('sometimes missing (%d/%d missing)', missingCount, typeCount);
            end

            fprintf('  - %s\n', fieldNames(f));
            fprintf('      presence: %d/%d (%s)\n', presentCounts(f), typeCount, statusText);
            fprintf('      example: %s\n', formatValue(fieldExamples{f}));

            fieldReports(f).name = fieldNames(f);
            fieldReports(f).presentCount = presentCounts(f);
            fieldReports(f).missingCount = missingCount;
            fieldReports(f).sometimesMissing = sometimesMissing;
            fieldReports(f).example = fieldExamples{f};
        end

        typeReports(t).type = typeName;
        typeReports(t).count = typeCount;
        typeReports(t).dataFields = fieldReports;
    end

    fprintf('\n=== End Event Log Schema Summary ===\n\n');

    report.eventTypes = typeReports;
end

function [fieldNames, presentCounts, examples] = collectTopLevelFieldStats(events)
    unionNames = strings(0, 1);
    for i = 1:numel(events)
        names = string(fieldnames(events(i)));
        unionNames = unique([unionNames; names], 'stable');
    end

    fieldNames = unionNames;
    presentCounts = zeros(numel(fieldNames), 1);
    examples = cell(numel(fieldNames), 1);

    for f = 1:numel(fieldNames)
        name = char(fieldNames(f));
        foundExample = false;
        for i = 1:numel(events)
            if isfield(events(i), name)
                presentCounts(f) = presentCounts(f) + 1;
                if ~foundExample
                    examples{f} = events(i).(name);
                    foundExample = true;
                end
            end
        end
        if ~foundExample
            examples{f} = [];
        end
    end
end

function [fieldNames, presentCounts, examples] = collectDataFieldStats(typeEvents)
    unionNames = strings(0, 1);
    for i = 1:numel(typeEvents)
        data = afField(typeEvents(i), 'data', struct());
        if isstruct(data)
            names = string(fieldnames(data));
            unionNames = unique([unionNames; names], 'stable');
        end
    end

    fieldNames = unionNames;
    presentCounts = zeros(numel(fieldNames), 1);
    examples = cell(numel(fieldNames), 1);

    for f = 1:numel(fieldNames)
        name = char(fieldNames(f));
        foundExample = false;
        for i = 1:numel(typeEvents)
            data = afField(typeEvents(i), 'data', struct());
            if isstruct(data) && isfield(data, name)
                presentCounts(f) = presentCounts(f) + 1;
                if ~foundExample
                    examples{f} = data.(name);
                    foundExample = true;
                end
            end
        end
        if ~foundExample
            examples{f} = [];
        end
    end
end

function text = formatValue(value)
    if isempty(value)
        text = '[]';
        return;
    end

    try
        if ischar(value)
            text = sprintf('''%s''', value);
            return;
        end

        if isstring(value)
            if isscalar(value)
                text = sprintf('"%s"', char(value));
            else
                text = sprintf('string[%s]', mat2str(size(value)));
            end
            return;
        end

        if isnumeric(value) || islogical(value)
            if isscalar(value)
                text = mat2str(value);
            else
                text = sprintf('%s %s', class(value), mat2str(size(value)));
            end
            return;
        end

        if isstruct(value)
            text = sprintf('struct with fields: %s', strjoin(fieldnames(value), ', '));
            return;
        end

        if iscell(value)
            text = sprintf('cell %s', mat2str(size(value)));
            return;
        end

        encoded = jsonencode(value);
        if strlength(string(encoded)) > 160
            text = sprintf('%s (truncated): %s...', class(value), extractBefore(string(encoded), 157));
            text = char(text);
        else
            text = char(string(encoded));
        end
    catch
        text = sprintf('<unprintable %s>', class(value));
    end
end
