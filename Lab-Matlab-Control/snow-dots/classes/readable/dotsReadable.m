classdef dotsReadable < handle
    %> @class dotsReadable
    %> Superclass for objects that read data.
    %> @details
    %> The dotsReadable superclass provides a uniform way to read data,
    %> such as data from a gamepad or eyetracker.  It imposes a format for
    %> data and provides utilities for previewing data and for defining,
    %> detecting and enqueing events of interest.
    %> @details
    %> dotsReadable itself is not a usable class.  Rather, it provides a
    %> uniform interface and core functionality for subclasses.  Subclasses
    %> must redefine the following methods in order to read actual data:
    %>   - openDevice()
    %>   - closeDevice()
    %>   - openComponents()
    %>   - closeComponents()
    %>   - readNewData()
    %>   .
    %> These methods are invoked internally.  They encapsulate the details
    %> of how to read from any particular device.  See the documentation for
    %> each of these methods for more information about how subclasses
    %> should redefine them.
    %> @details
    %> Users should expect to call public methods like initialize(),
    %> preview(), and read(), which are the same for all subclasses.
    %> @details
    %> dotsReadable() assumes that each input source or device has one or
    %> more components.  Each component must be assigned a small, positive,
    %> unique, integer ID.  This ID is used in many methods and properties
    %> to identify the component.  A component might be an individual button
    %> on a game pad, or a data channel from an eye tracker.
    %> @details
    %> For most properties and methods, data are formatted as matrix rows.
    %> Each row represents one measurement.  Each row has three columns:
    %> [ID, value, time].  The @b ID is the ID of a device component.  The
    %> @b value is any observed value.  The @b time is a timestamp
    %> associated with the @b value.
    %> @details
    %> Several properties use component ID as indexes.  For example, the
    %> state property has one row for each component.  If for some reason
    %> component IDs are non-sequential, the state property may have gaps
    %> between useful rows.  This is expected.  Using IDs as indices takes
    %> advantage of Matlab's array facility to provide quick, concise
    %> assignment and lookup of data.
    %> @details
    %> dotsReadable provides utilities for defining, detecting, and
    %> enqueueing events of interest.  Each component may define one event
    %> of interest at a time.  An event can be defined for one of four
    %> possibilities:
    %>   - the value of a component is less than some value
    %>   - the value of a component is greater than some value
    %>   - the value of a component is between two values
    %>   - the value of a component is not between two values
    %>   .
    %> Once defined, events are detected automatically during read() and can
    %> be read out sequentially from getNextEvent().  Event dectection
    %> relies heavily on the dotsReadable data format and ID indexes.
    properties
        %> whether or not the object is ready to read() from
        isAvailable = false;
        
        %> struct array with integer ID and details about each component
        components;
        
        %> matrix of ID, latest value, and latest time indexed by ID
        state;
        
        %> matrix of component ID, value, and time from previous read()
        history;
        
        %> whether or not to to invoke read() during getValue(), etc.
        isAutoRead = false;
        
        %> struct array defining events of interest, indexed by ID
        eventDefinitions;
        
        %> initial size of queue for events of interest
        initialEventQueueSize = 100;
        
        %> any function that returns the current time as a number
        clockFunction;
    end
    
    properties (SetAccess = protected)
        %> array of queued events (row indices into history)
        eventQueue;
        
        %> queue index of the next event to be dequeued
        queueNext;
        
        %> queue index of the last event enqueued
        queueLast;
    end
    
    methods
        %> Constructor takes no arguments.
        function self = dotsReadable()
            mc = dotsTheMachineConfiguration.theObject();
            mc.applyClassDefaults(self, mc.defaultGroup);
        end
        
        %> Locate, acquire, configure, etc. device and component resources.
        function initialize(self)
            %> protection from redundant initializations
            self.closeDevice();
            self.closeComponents();
            
            %> remove any stale component info
            names = {'name', 'ID'};
            padded = cell(1, 2*numel(names));
            padded(1:2:end) = names;
            self.components = struct(padded{:});
            
            %> try to open device and components from scratch
            isOpen = self.openDevice();
            if isOpen
                self.components = self.openComponents();
            end
            self.isAvailable = isOpen && ~isempty(self.components);
            
            %> remove any stale event definitions
            names = {'name', 'ID', 'lowValue', 'highValue', 'isInverted'};
            padded = cell(1, 2*numel(names));
            padded(1:2:end) = names;
            self.eventDefinitions = struct(padded{:});
            if self.isAvailable
                IDs = self.getComponentIDs();
                for id = IDs
                    self.undefineEvent(id);
                end
            end
            
            %> remove any stale data
            self.flushData();
        end
        
        %> Release any resources acquired by initialize().
        function close(self)
            self.closeComponents();
            self.closeDevice();
        end
        
        %> Automatically close when Matlab is done with this object.
        function delete(self)
            self.close();
        end
        
        %> Add incoming data to history and detect events of interest.
        %> @details
        %> read() updates device resources and components as defined by
        %> subclasses in readNewData().  It uses any new data to detect
        %> events of interest and enqueues any events in eventQueue.  It
        %> appends any new data to history and updates the component summary
        %> in state.
        %> @details
        %> read() should be called in order to get the latest device data.
        %> It may make sense to call read() periodically, or to call read()
        %> immediately before accessing history or state, or invoking
        %> getState(), getValue(), or getNextEvent().
        function read(self)
            newData = self.readNewData();
            if isempty(newData)
                return;
            end
            
            %> find events of interest in the new data
            isEvent = self.detectEvents(newData);
            if any(isEvent)
                historyIndices = size(self.history, 1) + find(isEvent);
                self.enqueueEvents(historyIndices);
            end
            
            %> append all new data to history
            self.history = cat(1, self.history, newData);
            
            %> deal new data into the current state
            %>   assumes data for each component are sorted
            newIDS = newData(:,1);
            self.state(newIDS,:) = newData;
        end
        
        %> Delete historical data and reset the current state.
        %> @details
        %> flushData() flush data deletes any data previously read.  This
        %> includes the object's state, history, and eventQueue.
        function flushData(self)
            %> make a blank state with room for each component
            IDs = self.getComponentIDs();
            maxID = max(IDs);
            self.state = zeros(maxID,3);
            self.state(IDs) = IDs;
            
            %> remove history of data and queued events
            self.history = zeros(0,3);
            self.resizeEventQueue(self.initialEventQueueSize, true);
        end
        
        %> Record current and historical data in topsDataLog.
        %> @details
        %> logData() saves all properties of a dotsReadable object as a
        %> struct in topsDataLog, using the class's name as the data group
        %> name.
        function logData(self)
            name = class(self);
            data = struct(self);
            topsDataLog.logDataInGroup(data, name);
        end
        
        %> Get the state of device components as of the given time.
        %> @param time a time in the past to consider instead of the current
        %> time
        %> @details
        %> getState() summarizes the latest data for each device component.
        %> getState() returns a nx3 matrix where each row has the form [ID,
        %> value, time].  Each @b ID identifies a device component.  Rows of
        %> the matrix are indexed by ID values.  Each @b value is the latest
        %> value that was read at each component.  Each @b time is the time
        %> when the corresponding value was read.
        %> @details
        %> By default, getState() returns the latest data.  If @a time is
        %> provided, components are summarized as of the given @a time and
        %> data read after the given @a time are ignored.
        %> @details
        %> If isAutoRead is set to true, invokes read() to update component
        %> data before summarizing.
        function stateAtTime = getState(self, time)
            if nargin < 2 || isempty(time)
                stateAtTime = self.state;
                return;
            end
            
            %> update component data before summarizing
            if self.isAutoRead
                disp('5');
                self.read();
                disp('6');
            end
            
            %> get the data history up to the given time
            isInTime = self.history(:,3) <= time;
            historyAtTime = self.history(isInTime,:);
            
            %> start with a blank state for all components
            IDs = self.getComponentIDs();
            maxID = max(IDs);
            stateAtTime = zeros(maxID,3);
            stateAtTime(IDs) = IDs;
            
            %> deal history data into the blank state
            %>   assumes data for each component are sorted
            historyIDs = historyAtTime(:,1);
            stateAtTime(historyIDs,:) = historyAtTime;
        end
        
        %> Get the latest value for the given component.
        %> @param ID one of the integer IDs in components
        %> @details
        %> Returns the latest value that was read for the component
        %> identified by @a ID.  Also returns as a second argument a data
        %> row of the form [ID, value, time], where the @b time is the time
        %> associated with the latest @b value.
        %> @details
        %> If isAutoRead is set to true, invokes read() to update component
        %> data before accessing values.
        function [value, data] = getValue(self, ID)
            
            %> update component data before accessing
            if self.isAutoRead
                self.read();
            end
            
            value = [];
            data = zeros(0,3);
            if ID > 0 && ID <= size(self.state, 1)
                value = self.state(ID,2);
                data = self.state(ID,:);
            end
        end
        
        %> Define the event of interest for one of the input components.
        %> @param ID one of the integer IDs in components
        %> @param name string name for an event of interest
        %> @param lowValue the lower bound on the event of interest
        %> @param highValue the upper bound on the event of interest
        %> @param isInverted whether to invert event detection logic
        %> @details
        %> defineEvent() sets parameters for detecting events of interest as
        %> the value of a component changes.  @a ID specifies which
        %> component.  Each component may define only one event of interest
        %> at a time, so repeated calls to defineEvent() with the same @a ID
        %> will replace previous event definitions.
        %> @details
        %> @a name is an arbitrary string identifying the event of
        %> interest.  @a lowValue and @a highValue define the boundaries of
        %> the event of interest.  When the value of the component falls
        %> between @a lowValue and @a highValue, an event of interest
        %> occurs.
        %> If @a isInverted is provided and equal to true, the definition of
        %> the event will be inverted.  The event will occur when the value
        %> of the component moves outside of @a lowValue and @a highValue.
        %> @details
        %> Events of interest are detected during read(), as new data
        %> arrive.  When events of interest are detected they are added to
        %> eventQueue.  Events can be read out one at a time later, with
        %> getNextEvent().
        %> @details
        %> Event does not use any timing information, so techniques like
        %> edge detection are not possible.  As a consequence, the number of
        %> events that occur may depend on the sampling frequency or
        %> noisiness of input sources.  To avoid redundant event detection,
        %> readNewData() may be implemented so as to smooth data, or the
        %> report data only when the value of a component changes.
        function defineEvent(self, ID, name, ...
                lowValue, highValue, isInverted)
            
            if nargin < 4 || isempty(lowValue)
                lowValue = -inf;
            end
            
            if nargin < 5 || isempty(highValue)
                highValue = inf;
            end
            
            if nargin < 6 || isempty(isInverted)
                isInverted = false;
            end
            
            %> fill in this event definition with given values
            self.eventDefinitions(ID).name = name;
            self.eventDefinitions(ID).ID = ID;
            self.eventDefinitions(ID).lowValue = lowValue;
            self.eventDefinitions(ID).highValue = highValue;
            self.eventDefinitions(ID).isInverted = isInverted;
        end
        
        %> Delete the event for one of the input components.
        %> @param ID one of the integer IDs in components
        %> @details
        %> Removes the event definition associated with @a ID.  The
        %> component with the given @a ID will no longer produce events of
        %> interest.
        function undefineEvent(self, ID)
            %> fill in this event definition with uninformative values
            self.eventDefinitions(ID).name = '';
            self.eventDefinitions(ID).ID = ID;
            self.eventDefinitions(ID).lowValue = nan;
            self.eventDefinitions(ID).highValue = nan;
            self.eventDefinitions(ID).isInverted = false;
        end
        
        %> Get the next event that was detected in read().
        %> @param isPeek whether to leave the next event in the queue
        %> @details
        %> getNextEvent() returns the @b name of the the next queued
        %> event of interest.  The name corresponds to one of the @b name
        %> values in eventDefinitions.  Also returns as second output the
        %> data which caused the event of interest.  The data corresponds to
        %> one of the rows of history.  Thus, the data has the form [ID,
        %> value, time].
        %> @details
        %> Additional information about the event can be found in
        %> eventDefinitions(ID).  Additional information about the component
        %> which caused the event can be found in components.
        %> @details
        %> By default, the next event is read out of the queue and removed.
        %> If @a isPeek is provided and true, the event is read out but left
        %> in the queue to be read again.
        %> @details
        %> If isAutoRead is set to true, invokes read() to update component
        %> data before getting the next event.
        function [name, data] = getNextEvent(self, isPeek)
            if nargin < 2 || isempty(isPeek)
                isPeek = false;
            end
            
            %> update component data before checking for events
            if self.isAutoRead
                self.read();
            end
            
            historyIndex = self.dequeueEvent(isPeek);
            if isempty(historyIndex) || historyIndex < 1
                name = '';
                data = zeros(0,3);
                
            else
                %> get queued data from hitory
                %>   look up the event name for convenience
                data = self.history(historyIndex, :);
                ID = data(1);
                name = self.eventDefinitions(ID).name;
            end
        end
        
        %> Get events that are happening at the current time.
        %> @param time a time in the past to consider instead of the current
        %> time.
        %> @details
        %> getHappeningEvent() summarizes events that are still happening,
        %> at the given @a time.  If @a time is omitted, defaults to the
        %> current time.  This contrasts with getNextEvent(), which recalls
        %> events that happened in the past.  getHappeningEvent() does not
        %> affect the behavior of getNextEvent() or the values in
        %> eventQueue.
        %> @details
        %> If no events are happening at the given time, returns ''.  If one
        %> or more events is happening, returns the name of the last event
        %> that happened.  Also returns as a second output the component ID
        %> for the last event.
        %> @details
        %> Also returns as a third output a cell array of names of all the
        %> events that are happening.  Also returns as a fourth output an
        %> array of component IDs for all the events that are happening.
        function [lastName, lastID, names, IDs] = ...
                getHappeningEvent(self, time)
            
            if nargin < 2 || isempty(time)
                stateAtTime = self.getState();
            else
                stateAtTime = self.getState(time);
            end
            
            allIDs = self.getComponentIDs();
            data = stateAtTime(allIDs, :);
            isEvent = self.detectEvents(data);
            if any(isEvent)
                IDs = allIDs(isEvent);
                eventData = stateAtTime(IDs,:);
                [lastTime, lastIndex] = max(eventData(:,2));
                lastID = eventData(lastIndex,1);
                lastName = self.eventDefinitions(lastID).name;
                names = {self.eventDefinitions(IDs).name};
            else
                lastName = '';
                lastID = [];
                IDs = [];
                names = {};
            end
        end
        
        %> Get the number of events in eventQueue.
        %> @detials
        %> Returns the number of events which are currently enqueued in
        %> eventQueue.
        function nEvents = getNumberOfEvents(self)
            nEvents = self.queueLast - self.queueNext + 1;
        end
        
        %> Get an array of unique integer component IDs.
        %> @details
        %> Returns an array of component IDs, which are unique, small,
        %> positive integers which identify device components.
        function IDs = getComponentIDs(self)
            IDs = [self.components.ID];
        end
        
        %> Get the current time from clockFunction.
        function time = currentTime(self)
            time = feval(self.clockFunction);
        end
        
        %> Open a figure with continuously read device data.
        %> @details
        %> Opens a new figure and plots component and event data.
        %> Continuously invokes read() and updates the plot as long as the
        %> figure is open.
        function plotData(self)
            if self.isAvailable
                
                %> only plot new data
                self.flushData();
                
                f = figure( ...
                    'MenuBar', 'none', ...
                    'ToolBar', 'none', ...
                    'NumberTitle', 'off', ...
                    'Name', class(self));
                
                %> plot component values on a y-axis
                names = {self.components.name};
                IDs = [self.components.ID];
                nComponents = numel(IDs);
                labels = cell(1, nComponents);
                for ii = 1:nComponents
                    labels{ii} = sprintf('%>d: "%>s"', IDs(ii), names{ii});
                end
                [sortedIDs, orderOfIDs] = sort(IDs);
                ax = subplot(1,2,1, ...
                    'Parent', f, ...
                    'YLim', [0, max(IDs)+1], ...
                    'YTick', sortedIDs, ...
                    'YTickLabel', labels(orderOfIDs), ...
                    'XTick', 0, ...
                    'XGrid', 'on');
                title(ax, 'component values');
                componentLine = line(zeros(1,nComponents), IDs, ...
                    'Parent', ax, ...
                    'LineStyle', 'none', ...
                    'Marker', '.');
                componentTexts = zeros(1, nComponents);
                for ii = 1:nComponents
                    componentTexts(ii) = text(0, IDs(ii), '');
                end
                
                %> plot events in a list box
                tempAx = subplot(1,2,2, ...
                    'Parent', f, ...
                    'Units', 'normalized');
                boxPos = get(tempAx, 'Position');
                titlePos = [boxPos(1) boxPos(2)+boxPos(4), boxPos(3), .05];
                delete(tempAx);
                
                eventStrings = {};
                list = uicontrol( ...
                    'Parent', f, ...
                    'Units', 'normalized', ...
                    'Position', boxPos, ...
                    'Style', 'listbox', ...
                    'Enable', 'inactive', ...
                    'String', eventStrings);
                uicontrol( ...
                    'Parent', f, ...
                    'BackgroundColor', get(f, 'Color'), ...
                    'Units', 'normalized', ...
                    'Position', titlePos, ...
                    'Style', 'text', ...
                    'Enable', 'inactive', ...
                    'String', 'detected events');
                
                %> update component and event plots
                while ishandle(f)
                    self.read();
                    
                    %> update component markers and text
                    componentData = self.state(IDs,2);
                    set(componentLine, 'XData', componentData);
                    for ii = 1:nComponents
                        paddedString = sprintf('  %>s', ...
                            num2str(componentData(ii)));
                        set(componentTexts(ii), ...
                            'String', paddedString, ...
                            'Position', [componentData(ii), IDs(ii)]);
                    end
                    
                    %> update list of detected events
                    while self.getNumberOfEvents > 0
                        [name, data] = self.getNextEvent();
                        ID = data(1);
                        time = data(3);
                        newString = sprintf('%>d: "%>s" at %>.2f', ...
                            ID, name, time);
                        eventStrings = cat(2, newString, eventStrings);
                        set(list, 'String', eventStrings);
                    end
                    
                    %> update axes to accomodate data range
                    vals = self.history(:,2);
                    if ~isempty(vals);
                        minVal = min(vals);
                        maxVal = max(vals);
                        set(ax, ...
                            'XTick', unique([minVal, maxVal]), ...
                            'XLim', [minVal-1, maxVal+1]);
                    end
                    
                    drawnow();
                    pause(0.05);
                end
            end
        end
    end
    
    methods (Access = protected)
        %> Locate and acquire input device resources (for subclasses).
        %> @details
        %> Subclasses must redefine openDevice().  They should expect
        %> openDevice() to be called during initialize() and when an object
        %> is constructed.  openDevice() should locate, acquire, configure,
        %> etc. major device resources required for reading data.  Specific
        %> resources relating to device components, like individual buttons
        %> of a gamepad, should be handled in openComponents().
        %> @details
        %> openDevice() should return true if resources were successfully
        %> acquired and individual components are ready to be opened.
        %> Otherwise, openDevice() should return false.
        function isOpen = openDevice(self)
            isOpen = false;
        end
        
        %> Release input device resources (for subclasses).
        %> @details
        %> Subclasses must redefine closedevice().  Any resources that
        %> were acquired by openDevice() should be released.  It should
        %> be safe to call closeDevice() multiple times in a row.
        function closeDevice(self)
            self.isAvailable = false;
        end
        
        %> Locate and acquire device components (for subclasses).
        %> @details
        %> Subclasses must redefine openComponents().  They should expect
        %> openComponents() to be called immediately after a successful call
        %> to openDevice(). Assuming the device was opened successfully,
        %> openComponents() should identify, acquire, configure, etc.
        %> specific components of interest, such as individual buttons on a
        %> gamepad.
        %> @details
        %> openComponents() must assign a name and a unique ID to each
        %> component.  Each name should be a short, human-readable string.
        %> Each ID should be a unique, small, greater-than-0 integer.
        %> @details
        %> openComponents() must return names and IDs as a struct array with
        %> fields @b ID and @b name.  The struct array should have one
        %> element per component.  Subclasses may add additional fields to
        %> the components struct array, but @b ID and @b name are mandatory.
        function components = openComponents(self)
            components = self.components;
        end
        
        %> Release device components (for subclasses).
        %> @details
        %> Subclasses must redefine closeComponents().  Any resources that
        %> were acquired by openComponents() should be released.  It should
        %> be safe to call closeComponentes() multiple times in a row.
        function closeComponents(self)
            self.isAvailable = false;
        end
        
        %> Read and format incoming data (for subclasses).
        %> @details
        %> Subclasses must redefine readNewData() to update input devices,
        %> read from device components, and put data in the expected
        %> format.
        %> @details
        %> readNewData() must return an nx3 matrix of data with rows of the
        %> form [ID, value, time].  Each @b ID must match one of the values
        %> in components.ID.  Each @b value should be a new value that was
        %> read from the component.  Each @b time should be a timestamp
        %> asociated with that value.  Only new data, which has not yet been
        %> read, should be returned from readNewData().
        function newData = readNewData(self)
            newData = zeros(0,3);
        end
        
        %> Use new data to look up events of interest (used internally).
        %> @param data nx3 matrix of component data
        %> @details
        %> Expects rows of @a data to have the form [ID, value, time].
        %> Uses ID values to look up parameters in eventDefinitions, and
        %> performs logical comparisons to determine which rows of @a
        %> data qualify as events of interest.
        %> @details
        %> Returns a logical array with one element per row of @a data.
        %> Where the array is true, the corresponding row of @a data
        %> qualifies as an event of interest.  If data is empty, returns
        %> [].
        function isEvent = detectEvents(self, data)
            if isempty(data)
                isEvent = false(1, 0);
                return;
            end
            
            %> look up the event definition for each incoming ID
            newIDs = data(:,1);
            definitions = self.eventDefinitions(newIDs);
            lows = [definitions.lowValue];
            highs = [definitions.highValue];
            isInverted = [definitions.isInverted];
            
            %> compare incoming values to event definitions
            newValues = data(:,2)';
            isInRange = (newValues <= highs) & (newValues >= lows);
            isEvent = xor(isInRange, isInverted);
        end
        
        %> Resize and optionally clear the event queue (used internally).
        %> @param minSize the new minimum size for eventQueue
        %> @param doClear whether or not to delete previously queued events
        %> @details
        %> Changes the size of eventQueue to agree with the given @a
        %> minSize.  If @a minSize is smaller than the number of events
        %> currently in eventQueue, the size of the queue remains unchanged.
        %> @details
        %> If @a doClear is true, deletes any previously queued events.
        %> This is a way to initialize eventQueue.  If doClear is false,
        %> packs any queued events into the beginning of eventQueue.  Events
        %> are re-packed regardless of @a minSize.
        %> @details
        %> Returns the new size of eventQueue, which is at least @a minSize.
        function newSize = resizeEventQueue(self, minSize, doClear)
            oldSize = numel(self.eventQueue);
            newSize = max(oldSize, minSize);
            queue = zeros(newSize, 1);
            
            nEvents = self.getNumberOfEvents();
            if doClear
                %> leave the queue empty and reset queue counters
                self.queueNext = 1;
                self.queueLast = 0;
                
            elseif nEvents > 0
                %> copy data from the old queue
                %>   to the begining of the new queue
                queue(1:nEvents) = ...
                    self.eventQueue(self.queueNext:self.queueLast);
                self.queueNext = 1;
                self.queueLast = nEvents;
            end
            self.eventQueue = queue;
        end
        
        %> Add events of interest to the event queue (used internally).
        %> @param eventValues array of values to add to eventQueue
        %> @details
        %> Adds one or more new @a eventValues to eventQueue and does queue
        %> accounting.  Returns the new total number of events in
        %> eventQueue.
        function nEvents = enqueueEvents(self, eventValues)
            %> resize the queue as needed
            queueSize = numel(self.eventQueue);
            nValues = numel(eventValues);
            if queueSize < (self.queueLast + nValues);
                newSize = 2*queueSize+nValues;
                self.resizeEventQueue(newSize, false);
            end
            self.eventQueue((1:nValues) + self.queueLast) = eventValues;
            self.queueLast = self.queueLast + nValues;
            
            nEvents = self.getNumberOfEvents();
        end
        
        %> Remove the next queued event of interest (used internally).
        %> @param isPeek whether to leave the next event in the queue
        %> @details
        %> Gets the next event from eventQueue and does queue accounting.
        %> If @a isPeek is provided and equal to true, leaves the event in
        %> the queue to be read again.  Otherwise, removes the event.
        %> @details
        %> Returns the next value queued in eventQueue.  If there are no
        %> queued values, returns [].  Returns as a second argument the new
        %> total number og events in eventQueue.
        function [eventValue, nEvents] = dequeueEvent(self, isPeek)
            eventValue = [];
            nEvents = self.getNumberOfEvents();
            if nEvents > 0
                eventValue = self.eventQueue(self.queueNext);
                
                if ~isPeek
                    self.queueNext = self.queueNext + 1;
                end
            end
        end
    end
    
    methods (Static)
        %> Is the named event happening now?
        %> @param readables array or cell array of dotsReadable objects
        %> @param eventName name of an event defined by @a readables
        %> @details
        %> Checks whether any of the given @a readables currently has an
        %> event happening with the given @a eventName.  Does not invoke
        %> read() for any readable.
        %> @details
        %> Returns true if any of given @a readables has @a eventName
        %> happening.  Returns as a second output the data associated with
        %> the event.  The data has the form [ID, value, time].  Returns as
        %> a third output the readable which has @a eventName happening.  If
        %> more than one of the given @a readables has @a eventName
        %> happening, only returns the first readable.
        function [isHappening, data, readable] = isEventHappening( ...
                readables, eventName)
            
            %> easier to work with cell
            if isobject(readables)
                readables = num2cell(readables);
            end
            
            nReadables = numel(readables);
            for ii = 1:nReadables
                
                %> get the events happening for this readable
                readable = readables{ii};
                [lastName, lastID, names, IDs] = ...
                    readable.getHappeningEvent();
                
                %> does any happening event match the given eventName?
                isEventName = strcmp(names, eventName);
                if any(isEventName)
                    isHappening = true;
                    happeningID = IDs(find(isEventName, 1, 'first'));
                    data = readable.state(happeningID, :);
                    return;
                end
            end
            
            isHappening = false;
            data = [];
            readable = [];
        end
        
        %> Wait for the named event to happen.
        %> @param readables array or cell array of dotsReadable objects
        %> @param eventName name of an event defined by @a readables
        %> @param maxWait maximum time to wait for @a eventName
        %> @details
        %> Waits for one of of the given @a readables to report that the
        %> given @a eventName happened.  @a maxWait specifies how long to
        %> wait before giving up.  Uses currentTime() of the first readable
        %> to keep track of time.  Invokes read() and checks each readable
        %> for events at least once, even if @a maxWait is zero or negative.
        %> @details
        %> Returns true if any of given @a readables reports that @a
        %> eventName happened before @a maxWait.  Returns as a second output
        %> the amout of time waited.  Returns as a third output the data
        %> associated with the event.  The data has the form [ID, value,
        %> time].  Returns as a fourth output the readable which reported @a
        %> eventName.  If more than one of the given @a readables reports @a
        %> eventName, only returns the first readable.
        function [didHappen, waitTime, data, readable] = waitForEvent( ...
                readables, eventName, maxWait)
            
            %> easier to work with cell since unlike objects can't combine
            if isobject(readables)
                readables = mat2cell(readables, ...
                    ones(1, size(readables, 1)), ...
                    ones(1, size(readables, 2)));
            end
            
            nReadables = numel(readables);
            clocker = readables{1};
            startTime = clocker.currentTime();
            loopCount = 0;
            isContinue = true;
            while isContinue
                %> choose a new readable without incurring a for loop
                ii = 1 + mod(loopCount, nReadables);
                loopCount = loopCount + 1;
                readable = readables{ii};
                
                %> get a queued event for this readable
                disp('3');
                readable.read();
                disp('4');
                [name, data] = readable.getNextEvent();
                if strcmp(name, eventName)
                    waitTime = clocker.currentTime() - startTime;
                    didHappen = true;
                    return;
                end
                
                isContinue = loopCount < nReadables ...
                    || (startTime + maxWait) > clocker.currentTime();
            end
            
            didHappen = false;
            waitTime = clocker.currentTime() - startTime;
            data = [];
            readable = [];
        end
    end
end