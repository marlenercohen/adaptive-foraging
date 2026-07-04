function session = afResolveSessionInput(sessionInput)
%AFRESOLVESESSIONINPUT Accept session struct or JSON path.

    if isstruct(sessionInput)
        session = sessionInput;
        return;
    end

    if ischar(sessionInput) || isstring(sessionInput)
        session = loadSession(sessionInput);
        return;
    end

    error('afResolveSessionInput:InvalidInput', ...
        'sessionInput must be a session struct or JSON file path.');
end
