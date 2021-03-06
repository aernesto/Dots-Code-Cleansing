function index_ = taskCohTimeLearn_timeQuest(varargin)
%Do a training time Quest for the cohTimeLearn task
%
%   index_ = taskCohTimeLearn_timeQuest(varargin)
%
%   optional eye tracker for fixation
%   lpHID choices
%
%   Read Quest threshold from dXtask.userData
%
%   index_ specifies the new instance in ROOT_STRUCT.dXtask

% copyright 2008 Benjamin Heasly University of Pennsylvania

% name for this task
name = mfilename;


if nargin >= 3

    % ASL and sound info
    settings = varargin{1};

    % number of trials
    numTrials = varargin{2};

    % a function that allows repeat of the coherence Quest?
    endFcn = varargin{3};
    
    % Name suffix
    suffix = varargin{4};

    varargin(1:4) = [];
else
    warning(sprintf('%s using default values', mfilename));
    settings.useASL = true;
    settings.mouseMode = false;
    settings.mute = false;
    settings.dotDir = [0 180];
    settings.viewingTimes = [100 200 400 800];
    numTrials = 10;
    endFcn = {};
end

% number of trials and nuber of dXtc conditons
%   give the number of blocks
numBlocks = ceil(numTrials/length(settings.dotDir));

qGuesses = num2cell(settings.viewingTimes)

% dXquest to asses 81% correct viewing time at a particular coherence
arg_dXquest = { ...
    'stimRange',    [10, 3000], ...
    'stimValues',   [], ...
    'refStim',      200, ...
    'blankStim',	[], ...
    'guessStim',    300, ...
    'Tstd',         9, ...
    'estimateType', 'mean', ...
    'psychParams',  [0 2.5 .01 .5], ...
    'goPastConvergence', true, ...
    'name',         'timeQ81', ...
    'ptr',          {{}}, ...
    'showPlot',     false};

% dXtc just to randomize dot direction
arg_dXtc = { ...
    'name',     {'dot_dir', 'coherence'}, ...
    'values',	{settings.dotDir, nan}, ...
    'ptr',      {{'dXdots', 1, 'direction'}, {'dXdots', 1, 'coherence'}}};

arg_dXlr = { ...
    'ptr',      {{'dXdots', 1, 'direction'}}};

% args to make statelist polymorphic
ptrs = {'dXtc', 'dXquest', 'dXlr'};
vtcon = {'wait', {'dXquest', 1, 'value'}, []};
PQ = {};
arg_statelist = {ptrs, vtcon, PQ, settings};

% {'group', reuse, set now, set always}
reswap = {'current', false, true, false};
ta = cohTimeLearn_task_args;
index_ = rAdd('dXtask', 1, {'root', false, true, false}, ...
    'name',         [name(5:end) suffix] , ...
    'blockReps',    numBlocks, ...
    'userData',     100, ...
    'startTaskFcn', {@cohTimeLearn_readCohThresh}, ...
    'endTaskFcn',   endFcn, ...
    'helpers', ...
    { ...
    'dXquest',                  1,  reswap, arg_dXquest; ...
    'dXtc',                     2,  reswap, arg_dXtc; ...
    'dXlr',                     1,  reswap, arg_dXlr; ...
    'gXcohTimeLearn_hardware',	1,  true,   {settings}; ...
    'gXcohTimeLearn_graphics',	1,  true,	{settings}; ...
    'gXcohTimeLearn_statelist',	1,  false,	arg_statelist; ...
    }, ...
    ta{:}, varargin{:});