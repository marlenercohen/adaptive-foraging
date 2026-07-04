function episodeNumbers = afUnionEpisodeNumbers(varargin)
%AFUNIONEPISODENUMBERS Gather unique episode numbers from event arrays.

    values = [];
    for k = 1:nargin
        events = varargin{k};
        for i = 1:numel(events)
            data = afField(events(i), 'data', struct());
            ep = afField(data, 'episodeNumber', NaN);
            if ~isnan(ep)
                values(end + 1, 1) = ep; %#ok<AGROW>
            end
        end
    end

    if isempty(values)
        episodeNumbers = zeros(0, 1);
    else
        episodeNumbers = unique(values);
    end
end
