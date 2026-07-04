function events = afEventsByType(session, typeName)
%AFEVENTSBYTYPE Return session events matching one type.

    allEvents = afField(session, 'eventLog', struct([]));
    if isempty(allEvents)
        events = struct([]);
        return;
    end

    keep = false(numel(allEvents), 1);
    for i = 1:numel(allEvents)
        keep(i) = strcmp(afField(allEvents(i), 'type', ''), typeName);
    end

    events = allEvents(keep);
end
