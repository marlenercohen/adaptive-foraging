function value = afField(s, fieldName, defaultValue)
%AFFIELD Safe struct field access with default.

    if nargin < 3
        defaultValue = [];
    end

    value = defaultValue;
    if isstruct(s) && isfield(s, fieldName)
        value = s.(fieldName);
    end
end
