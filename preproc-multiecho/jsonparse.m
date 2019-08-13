function [out] = jsonparse(s)
%--------------------------------------------------------------
% Minimally formats a raw .json text outputted by MATLAB's jsonencode()
% function so that it is visually more readable
%
% Input
%   - s : character array outputted by MATLAB's jsonencode() function
%
% Output
%   - out : reformatted character array where all objects are listed
%           vertically and indented with a tab
%
% Method
%   - The script first finds positions of all commas that separate objects, 
%     excluding commas that separate array elements
%   - Then adds a newline and tab after the end of each such comma
%   - Then adds a newline and tab after the start of each object, 
%     and a newline before the end of each object
% 
% Notes
%   - for .json format, see https://www.json.org/
%
% Author : Andres Tamm
%--------------------------------------------------------------

% Get positions of all commas
p = regexp(s, ',', 'start')';

% Get start and end positions of array objects (arrays start with [ and end with ])
aStart = regexp(s, '[', 'start')';
aEnd   = regexp(s, ']', 'start')';

% Get positions of all characters that belong to arrays
a = [];
for i = 1:numel(aStart)
    tmp = aStart(i):aEnd(i);
    a = [a tmp];
end

% Get positions of all commas that separate objects
po = setdiff(p, a);

% Add newline and tab after the end of each comma that separates objects
% Updating the positions of commas that separate objects
for i = 1:numel(po)
    r    = ',\n\t';
    idx  = po(i);
    s    = [s(1:idx-1) r s(idx+1:end)];
    po = po + numel(r)-1;
end

% Add newline and tab after the start of each object
s = strrep(s, '{', '{\n\t');

% Add newline before the end of each object
s = strrep(s, '}', '\n}');

% Compose, so that newlines and tabs become actual new lines and tabs
s = compose(s);
s = s{1};

% Output
out = s;

end