function out = afMoveEventsForEpisode(session, moveType, episodeNumber)
%AFMOVEEVENTSFOREPISODE Filter move events by type and episode number.

    events = afEventsByType(session, moveType);
    keep = false(numel(events), 1);
    for i = 1:numel(events)
        data = afField(events(i), 'data', struct());
        keep(i) = isequal(afField(data, 'episodeNumber', NaN), episodeNumber);
    end

    out = events(keep);
end
