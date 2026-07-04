function out = afRewardEventsForEpisode(rewardEvents, episodeNumber)
%AFREWARDEVENTSFOREPISODE Filter reward events by episode number.

    keep = false(numel(rewardEvents), 1);
    for i = 1:numel(rewardEvents)
        data = afField(rewardEvents(i), 'data', struct());
        keep(i) = isequal(afField(data, 'episodeNumber', NaN), episodeNumber);
    end

    out = rewardEvents(keep);
end
