function stimuli = buildStimulusTable(session)
%BUILDSTIMULUSTABLE Build one metadata table row per stimulus.
%   STIMULI = BUILDSTIMULUSTABLE(SESSION) reads stimulus metadata from
%   SESSION.SESSIONMETADATA.STIMULUSMETADATA (as produced by LOADSESSION),
%   iterates all stimulus sets, and returns a table with one row per
%   stimulus and the variables:
%       stimulusID, category, contrast, orientation, curvature, sharpness
%
%   The metadata field mapping is:
%       metadatamtx1 -> category
%       metadatamtx2 -> contrast
%       metadatamtx3 -> orientation
%       metadatamtx4 -> curvature
%       metadatamtx5 -> sharpness

    if nargin < 1
        error('buildStimulusTable:MissingInput', 'session is required.');
    end
    if ~isstruct(session)
        error('buildStimulusTable:InvalidInputType', 'session must be a struct returned by loadSession().');
    end

    sessionMetadata = afField(session, 'sessionMetadata', struct());
    stimulusMetadata = afField(sessionMetadata, 'stimulusMetadata', struct());
    if ~isstruct(stimulusMetadata)
        error('buildStimulusTable:MissingStimulusMetadata', ...
            'session.sessionMetadata.stimulusMetadata must be a struct of stimulus sets.');
    end

    setNames = fieldnames(stimulusMetadata);

    stimulusID = zeros(0, 1);
    category = zeros(0, 1);
    contrast = zeros(0, 1);
    orientation = zeros(0, 1);
    curvature = zeros(0, 1);
    sharpness = zeros(0, 1);

    % Track IDs globally so duplicates across sets fail fast and explicitly.
    seenIDs = containers.Map('KeyType', 'char', 'ValueType', 'char');

    for setIdx = 1:numel(setNames)
        setName = setNames{setIdx};
        rows = stimulusMetadata.(setName);

        if isempty(rows)
            continue;
        end
        if ~isstruct(rows)
            error('buildStimulusTable:InvalidSetType', ...
                'Stimulus set "%s" must decode as a struct array.', setName);
        end

        for rowIdx = 1:numel(rows)
            row = rows(rowIdx);
            id = parseStimulusID(row, setName, rowIdx);

            key = sprintf('%.15g', id);
            if isKey(seenIDs, key)
                previousLocation = seenIDs(key);
                error('buildStimulusTable:DuplicateStimulusID', ...
                    'Duplicate stimulus ID %g encountered in %s[%d]; already seen in %s.', ...
                    id, setName, rowIdx, previousLocation);
            end
            seenIDs(key) = sprintf('%s[%d]', setName, rowIdx);

            features = afField(row, 'features', struct());
            if ~isstruct(features)
                error('buildStimulusTable:InvalidFeatures', ...
                    'Stimulus %g in set "%s" has invalid features; expected a struct.', id, setName);
            end

            stimulusID(end + 1, 1) = id; %#ok<AGROW>
            category(end + 1, 1) = parseNumericField(features, 'metadatamtx1', NaN); %#ok<AGROW>
            contrast(end + 1, 1) = parseNumericField(features, 'metadatamtx2', NaN); %#ok<AGROW>
            orientation(end + 1, 1) = parseNumericField(features, 'metadatamtx3', NaN); %#ok<AGROW>
            curvature(end + 1, 1) = parseNumericField(features, 'metadatamtx4', NaN); %#ok<AGROW>
            sharpness(end + 1, 1) = parseNumericField(features, 'metadatamtx5', NaN); %#ok<AGROW>
        end
    end

    stimuli = table( ...
        stimulusID, ...
        category, ...
        contrast, ...
        orientation, ...
        curvature, ...
        sharpness, ...
        'VariableNames', { ...
            'stimulusID', ...
            'category', ...
            'contrast', ...
            'orientation', ...
            'curvature', ...
            'sharpness' ...
        } ...
    );

    if ~isempty(stimuli)
        stimuli = sortrows(stimuli, 'stimulusID');
    end
end

function id = parseStimulusID(row, setName, rowIdx)
%PARSESTIMULUSID Parse and validate one stimulus ID.

    id = parseNumericField(row, 'id', NaN);
    if isnan(id) || ~isfinite(id)
        error('buildStimulusTable:InvalidStimulusID', ...
            'Stimulus in set "%s" at index %d has missing or invalid id.', setName, rowIdx);
    end
end

function value = parseNumericField(s, fieldName, defaultValue)
%PARSENUMERICFIELD Read a scalar numeric field with safe coercion.

    rawValue = afField(s, fieldName, defaultValue);

    if isnumeric(rawValue) || islogical(rawValue)
        if isempty(rawValue)
            value = defaultValue;
            return;
        end
        value = double(rawValue(1));
        return;
    end

    if isstring(rawValue) || ischar(rawValue)
        numericValue = str2double(string(rawValue));
        if isnan(numericValue)
            value = defaultValue;
        else
            value = numericValue;
        end
        return;
    end

    value = defaultValue;
end