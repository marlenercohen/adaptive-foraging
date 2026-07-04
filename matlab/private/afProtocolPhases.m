function phases = afProtocolPhases(protocol)
%AFPROTOCOLPHASES Normalize protocol phases to struct array.

    phases = afField(protocol, 'phases', struct([]));
    if ~isstruct(phases)
        phases = struct([]);
    end
end
