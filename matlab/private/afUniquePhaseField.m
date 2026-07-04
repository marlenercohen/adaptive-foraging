function values = afUniquePhaseField(phases, fieldName)
%AFUNIQUEPHASEFIELD Collect unique phase-level field values.

    values = {};
    if isempty(phases)
        return;
    end

    signatures = strings(0, 1);
    for i = 1:numel(phases)
        v = afField(phases(i), fieldName, []);
        sig = jsonencode(v);
        if ~any(signatures == sig)
            signatures(end + 1, 1) = sig; %#ok<AGROW>
            values{end + 1, 1} = v; %#ok<AGROW>
        end
    end
end
