function [dataFileName, taskPhase, id] = gatherTAFCDotsSubInfoQuest(tag, id, session, foldername)
% GATHERSUBINFO requests information about subject number and ID code.
% Creates a unique filename for saving the data.  Returns some relevant
% info in dataHeader.

if ~exist('tag','var')
    tag = input('experiment name (for saving)','s');
end

% if no id is specified, ask for a subject ID
if ~exist('id','var')
    id = input('Subject ID:  ','s');
end

% try to use the subject progress structure to determine phase and cbal

%Justin_TODO: The following asks for the phase from a list of possible
%phases. This is only used to name the file. Consider to remove/add in as
%argument to function to automate naming if phase specification is
%neccesary.
%Justin_Update: task phase so far is neccesary. It is returned after
%function call ends. May be used for something down the road.

%list all possible phases. 
%phaseLabels = {'demo', 'main'};
taskPhase = 'main';
%Justin skips this and declares all will be main
% User will be then prompted on which phase they are currently in.
% while isempty(taskPhase)
%      fprintf('Task phase:\n');
%      for i = 1:length(phaseLabels)
%          fprintf('  %d = %s\n',i,phaseLabels{i});
%      end
%      if prompt==1
%          phaseIdx = input('Enter the phase:  ');
%          if ismember(phaseIdx,1:length(phaseLabels))
%              taskPhase = phaseLabels{phaseIdx};
%          end
%      end   
% end


% set session number, ensuring a unique filename
if ~exist('session','var')
    session = 1;
end

if ~exist('foldername','var')
    foldername = input('folder to place saved results','s');
end

% Checks if a filealready exists with the same name
nameVetted = false;
while ~nameVetted
    dataFileName = fullfile(foldername, sprintf('%s_%s_%s_%d',tag,id,taskPhase,session));
    if exist(sprintf('%s.mat',dataFileName),'file')==2
        session = session+1;
    elseif exist(sprintf('%s.txt',dataFileName),'file')==2
        session = session+1;
    else
        nameVetted = true;
    end
end

% if prompt==1
% input(['Data will be saved in:\n  ',dataFileName,'\n  (ENTER to continue)']);
% end


