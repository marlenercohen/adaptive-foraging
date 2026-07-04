function rules = afRulesEncountered(session, phases)
%AFRULESENCOUNTERED Collect unique rule identifiers encountered.

    ruleList = strings(0, 1);

    startEvents = afEventsByType(session, 'episode_start');
    for i = 1:numel(startEvents)
        data = afField(startEvents(i), 'data', struct());
        ruleFile = string(afField(data, 'ruleFile', ""));
        phaseName = string(afField(data, 'phaseName', ""));
        if strlength(ruleFile) > 0
            ruleList(end + 1, 1) = ruleFile; %#ok<AGROW>
        elseif strlength(phaseName) > 0
            ruleList(end + 1, 1) = phaseName; %#ok<AGROW>
        end
    end

    if isempty(ruleList)
        for i = 1:numel(phases)
            ruleFile = string(afField(phases(i), 'ruleFile', ""));
            phaseName = string(afField(phases(i), 'name', ""));
            if strlength(ruleFile) > 0
                ruleList(end + 1, 1) = ruleFile; %#ok<AGROW>
            elseif strlength(phaseName) > 0
                ruleList(end + 1, 1) = phaseName; %#ok<AGROW>
            end
        end
    end

    ruleList = unique(ruleList);
    ruleList(ruleList == "") = [];
    rules = cellstr(ruleList);
end
