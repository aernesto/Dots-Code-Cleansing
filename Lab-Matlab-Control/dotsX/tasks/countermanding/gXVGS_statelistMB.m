function states_ = gXVGS_statelist(varargin)
%Get the statelist configuration for the simple_demo taskv
%
%   states_ = gXsimpleDemo_statelist(varargin)
%
%   gXsimpleDemo_statelist returns a cell array of configuration parameters
%   for all the states that make up the simple_demo task.  This set of
%   states will be traversed once per trial.  In pseudocode the statelist
%   is:
%
%   1. "clear"      clear all graphics from the screen
%   2. "fixOn"      show the fixation point, wait 200ms
%   3. "ready1"     play a tone, wait 100ms
%   4. "newDots"	pick new dot direction and coherence, wait 800ms
%   5. "ready2"     play a tone, wait 100ms
%   6. "dotsOn"     animate the dots for 1000ms
%   7. "respond"    wait up to 1000ms for a response
%   8. "left"       subject responsed "left", was this correct?
%   9. "right"      subject responsed "right", was this correct?
%   10. "correct"   correct response, play coin sound
%   11. "cText"     show the "correct" feedback text, wait 500ms
%   12. "incorrect"	incorrect response, play damage sound
%   13. "iText"     show the "incorrect" feedback text, wait 500ms
%   14. "error"     invalid response or no response, play 5 scolding beeps
%   15. "eText"     show the "invalid!" feedback text, wait 1000ms
%   15. "end"       the end of the trial
%
%   states_ is a cell of the form
%       {'dXstate', number_of_states, rAdd_args, statelist}
%   See below for details.
%
%   This is the form expected by the rGroup function, so invoking
%       rGroup('gXsimpleDemo_statelist')
%   will add all of the configured states to ROOT_STRUCT.
%
%   gXsimpleDemo_statelist may also be included as a helper for a dXtask,
%   in which case the configured states will be added to the ROOT_STRUCT
%   for that task.
%
%   varargin is ignored.
%
%   See also rGroup, rAdd, taskSimpleDemo

% 2008 by Benjamin Heasly
%   University of Pennsylvania
%   benjamin.heasly@gmail.com
%   (written in the Black Hills of South Dakota!)

% Define what happens when the subject presses the keyboard.  These "query
% mappings" can be different for each state, we can define seveal different
% mappings. Here we need only two.

% This query mapping means: check the dXkbHID hardware device (i.e. the
% keyboard).  If there has been any event (i.e. a keypress) then go to the
% state called "error".
noTouch = {'dXkbHID',  {'any', 'error'}};

% This mapping categorizes the subject's response as either "left", "right"
% or invalid
% respond = { 'dXkbHID',  {'f', 'left', 'j', 'right', 'any', 'error'}};
respond = { 'dXkbHID',  {'g', 'left', 'k', 'right', 'any', 'error'}};


% In this task, the correct response will change randomly each trial.  So
% we need a way to check whether "left" or "right" is correct.  These
% "conditionalizations" check the 'direction' property of the dXdots
% stimulus.  Depending on this angle, the conditionalization will
% change the path through the statelist for each trial.

% This conditionalization means: check the 'direction' property of the
% dXtarget1 object #1.  If the value is -2, then "left" was the correct
% choice and we should jump to thestate called "correct".  If the value was
% 2 then "left" was incorrect so jump to the state called "incorrect".
left_cond = ...
    {'jump', {'dXtarget', 2, 'x'}, [-7 7], {'correct'; 'incorrect'}};

% This one is similar, but checks whether "right" was the correct or
% incorrect choice.
right_cond = ...
    {'jump', {'dXtarget', 2, 'x'}, [-7 7], {'incorrect'; 'correct'}};


% Define some shorthand, which will make it easier to write the satelist,
% below.  These are functions that the state should invoke and arguments to
% those functions

% shorthand for showing fixation point, dots, and feedback text
GS = @rGraphicsShow;
fix = {'dXtarget', 1};
target = {'dXtarget', 2};
tx = 'dXtext';
nofix = {{}, 'dXtarget', 1};


% shorthand for playing beeps and sounds
SP = @rPlay;
bp = 'dXbeep';
sd = 'dXsound';

% shorthand for updating "control" objects dXtc and dXlr
VU = @rVarUpdate;

% Define the actual statelist.  Each state has 9 key properties:
%   1. a name, which must be unique
%   2. a function to invoke (optional)
%   3. arguments for the function (optional)
%   4. a "jump" state: the name of the state to go to after this one
%       'next'  = go to whatever state is next in the statelist
%       'x'     = last state, end of trial
%   5. an amount of time to wait before jumping to the next state
%   6. number of times to repeat this state *in addition to* the first time
%   7. a draw command for graphics:
%       0 = don't do any drawing--don't change graphics that are displayed
%       1 = draw continuously during the "wait" time
%       2 = draw continuously during the "wait" time (graphics accumulate)
%       3 = draw one new frame
%       4 = draw one new frame (graphics accumulate)
%       5 = clear all graphics and flip to a blank frame
%   8. a "query mapping", as defined above.
%       0 = use no mapping
%       1 = retain mapping from previous state
%   9 a "conditionalization", as defined above.
%       {} = use no conditionalization.

%   name        fun args        jump    wait    repsDrawQuery   cond
arg_dXstate = {{ ...
    'clear',    {}, {},         'next', 0,      0,  5,  0,      {}; ...
    'ready1',	SP, {bp,1},     'next', 1000,	0,  0,  noTouch,{}; ...
%   'newfix',   VU, {'dXtc'},	'next', 0,      0,  0,  1,      {}; ...
    'fixOn',    GS, fix,        'next', 800,	0,  3,  0,      {}; ...  
    'fixOff',   GS, nofix,      'next', 0,      0,  3,  0,      {}; ...
    'newtarget',VU, {'dXtc'},	'next', 0,      0,  0,  1,      {}; ...
    'targetOn', GS, target,     'next', 0,      0,  3,  0,      {}; ...
    'respond',  {}, {},         'incorrect',800,    0,  3,  respond,{}; ...
    'left',     {}, {},         'error',0,      0,  0,  0,      left_cond; ...
    'right',	{}, {},         'error',0,      0,  0,  0,      right_cond; ...
    'correct',  SP, {sd,1},     'end',	0,      0,  0,  0,      {}; ...
    'incorrect',SP, {sd,2},     'end',	0,      0,  0,  0,      {}; ...
    'error',    SP, {bp,1},     'end',  100,	4,  0,  0,      {}; ...
    'end',      {}, {},         'x',    0,      0,  5,  0,      {}; ...
    }};
numStates = size(arg_dXstate{1}, 1);

% configure the rAdd_args.  This tells rAdd four things:
%   1. What group should these objects belong to?  'current' means add
%   objects to whatever group is currently active (e.g. the current task). 
%
%   2. Should rAdd try to reuse existing objects of the same type?  If so,
%   rAdd will configure some existing objects rather than create new ones.
%
%   3. Should rAdd configure objects with rSet immediately upon creation?
%
%   4. Should rGroup reconfigure the object with rSet every time rGroup
%   activates this object (e.g. every time the task is activated)?
rAdd_args = {'current', false, true, false};

states_ = {'dXstate', numStates, rAdd_args, arg_dXstate};