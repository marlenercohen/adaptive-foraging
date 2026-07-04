function session = loadSession(jsonPath)
%LOADSESSION Load one Adaptive Foraging exported JSON session.
%   SESSION = LOADSESSION(JSONPATH) reads a single exported session log and
%   returns a normalized MATLAB struct with stable fields used by the
%   analysis functions in this package.

    if nargin < 1
        error('loadSession:MissingInput', 'jsonPath is required.');
    end

    if ~(ischar(jsonPath) || isstring(jsonPath))
        error('loadSession:InvalidInputType', 'jsonPath must be a char or string.');
    end

    jsonPath = char(jsonPath);
    if ~isfile(jsonPath)
        error('loadSession:FileNotFound', 'File not found: %s', jsonPath);
    end

    rawText = fileread(jsonPath);
    raw = jsondecode(rawText);

    session = struct();
    session.sourceFile = jsonPath;
    session.schemaVersion = afField(raw, 'schemaVersion', "");
    session.sessionMetadata = afField(raw, 'sessionMetadata', struct());
    session.eventLog = afField(raw, 'eventLog', struct([]));
    session.stateSnapshots = afField(raw, 'stateSnapshots', struct([]));
    session.internalErrors = afField(raw, 'internalErrors', struct([]));
    session.raw = raw;

    if ~isstruct(session.eventLog)
        session.eventLog = struct([]);
    end
    if ~isstruct(session.stateSnapshots)
        session.stateSnapshots = struct([]);
    end
    if ~isstruct(session.internalErrors)
        session.internalErrors = struct([]);
    end

    % Precompute event types for quick filtering in downstream summaries.
    if isempty(session.eventLog)
        session.eventTypes = strings(0, 1);
    else
        session.eventTypes = strings(numel(session.eventLog), 1);
        for i = 1:numel(session.eventLog)
            session.eventTypes(i) = string(afField(session.eventLog(i), 'type', ""));
        end
    end
end
