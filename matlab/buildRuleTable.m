function rules = buildRuleTable(session)
%BUILDRULETABLE Build one descriptive row per rule definition.
%   RULES = BUILDRULETABLE(SESSION) reads rule definitions from
%   SESSION.SESSIONMETADATA.RULEDEFINITIONS (as produced by LOADSESSION)
%   and returns a table with one row per rule and variables:
%       ruleName, ruleType, feature, operator, value
%
%   This helper supports rule definitions that contain exactly one rule
%   object, for example:
%       [{"type":"feature","feature":"metadatamtx1","operator":"==","value":3}]
%
%   Metadata feature keys are mapped to human-readable names:
%       metadatamtx1 -> category
%       metadatamtx2 -> contrast
%       metadatamtx3 -> orientation
%       metadatamtx4 -> curvature
%       metadatamtx5 -> sharpness

    if nargin < 1
        error('buildRuleTable:MissingInput', 'session is required.');
    end
    if ~isstruct(session)
        error('buildRuleTable:InvalidInputType', 'session must be a struct returned by loadSession().');
    end

    sessionMetadata = afField(session, 'sessionMetadata', struct());
    ruleDefinitions = afField(sessionMetadata, 'ruleDefinitions', struct());
    if ~isstruct(ruleDefinitions)
        error('buildRuleTable:MissingRuleDefinitions', ...
            'session.sessionMetadata.ruleDefinitions must be a struct keyed by rule file name.');
    end

    ruleNames = fieldnames(ruleDefinitions);

    ruleNameCol = strings(0, 1);
    ruleTypeCol = strings(0, 1);
    featureCol = strings(0, 1);
    operatorCol = strings(0, 1);
    valueCol = zeros(0, 1);

    for i = 1:numel(ruleNames)
        ruleName = string(ruleNames{i});
        definitionArray = ruleDefinitions.(ruleNames{i});

        definition = validateSingleRuleDefinition(definitionArray, ruleName);
        ruleType = string(afField(definition, 'type', ""));

        feature = missing;
        operator = missing;
        value = NaN;

        if ruleType == "feature"
            featureKey = string(afField(definition, 'feature', ""));
            if strlength(featureKey) == 0
                error('buildRuleTable:MissingFeatureField', ...
                    'Rule "%s" is missing required field "feature".', ruleName);
            end

            operator = string(afField(definition, 'operator', ""));
            if strlength(operator) == 0
                error('buildRuleTable:MissingOperatorField', ...
                    'Rule "%s" is missing required field "operator".', ruleName);
            end

            feature = mapFeatureName(featureKey);
            value = parseRuleValue(definition, ruleName);
        end

        ruleNameCol(end + 1, 1) = ruleName; %#ok<AGROW>
        ruleTypeCol(end + 1, 1) = ruleType; %#ok<AGROW>
        featureCol(end + 1, 1) = feature; %#ok<AGROW>
        operatorCol(end + 1, 1) = operator; %#ok<AGROW>
        valueCol(end + 1, 1) = value; %#ok<AGROW>
    end

    rules = table( ...
        ruleNameCol, ...
        ruleTypeCol, ...
        featureCol, ...
        operatorCol, ...
        valueCol, ...
        'VariableNames', {'ruleName', 'ruleType', 'feature', 'operator', 'value'} ...
    );

    if ~isempty(rules)
        rules = sortrows(rules, 'ruleName');
    end
end

function definition = validateSingleRuleDefinition(definitionArray, ruleName)
%VALIDATESINGLERULEDEFINITION Ensure exactly one rule object.

    if ~isstruct(definitionArray)
        error('buildRuleTable:InvalidRuleDefinitionType', ...
            'Rule "%s" must be a struct array decoded from a JSON array.', ruleName);
    end

    if numel(definitionArray) ~= 1
        error('buildRuleTable:UnsupportedRuleArity', ...
            ['Rule "%s" contains %d conditions. buildRuleTable currently supports ', ...
             'only definitions with exactly one rule object.'], ...
            ruleName, numel(definitionArray));
    end

    definition = definitionArray(1);
end

function readableName = mapFeatureName(featureKey)
%MAPFEATURENAME Map metadata feature keys to human-readable labels.

    switch char(featureKey)
        case 'metadatamtx1'
            readableName = "category";
        case 'metadatamtx2'
            readableName = "contrast";
        case 'metadatamtx3'
            readableName = "orientation";
        case 'metadatamtx4'
            readableName = "curvature";
        case 'metadatamtx5'
            readableName = "sharpness";
        otherwise
            % Preserve unknown feature names to keep output informative.
            readableName = featureKey;
    end
end

function value = parseRuleValue(definition, ruleName)
%PARSERULEVALUE Parse one scalar numeric rule value.

    rawValue = afField(definition, 'value', NaN);

    if isnumeric(rawValue) || islogical(rawValue)
        if isempty(rawValue)
            error('buildRuleTable:MissingValueField', ...
                'Rule "%s" is missing required field "value".', ruleName);
        end
        value = double(rawValue(1));
        return;
    end

    if ischar(rawValue) || isstring(rawValue)
        parsed = str2double(string(rawValue));
        if isnan(parsed)
            error('buildRuleTable:InvalidValueField', ...
                'Rule "%s" has non-numeric "value" (%s).', ruleName, string(rawValue));
        end
        value = parsed;
        return;
    end

    error('buildRuleTable:InvalidValueField', ...
        'Rule "%s" has unsupported "value" type (%s).', ruleName, class(rawValue));
end