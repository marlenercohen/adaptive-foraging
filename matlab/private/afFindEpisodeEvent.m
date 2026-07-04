function event = afFindEpisodeEvent(events, episodeNumber)
%AFFINDEPISODEEVENT Return the first event matching an episode number.

    event = [];
    for i = 1:numel(events)
        data = afField(events(i), 'data', struct());
        ep = afField(data, 'episodeNumber', NaN);
        if isequal(ep, episodeNumber)
            event = events(i);
            return;
        end
    end
end
