Screen('Preference','SkipSyncTests',1);
%AssertOpenGL;

ipAddress = input('SimpleGazeTracker address: ','s');
logfilename = input('log file name: ','s');

settings = {
	{'RECORDED_EYE', 'L'},...
	{'SCREEN_ORIGIN', 'TopLeft'},...
	{'TRACKER_ORIGIN', 'TopLeft'},...
	{'SCREEN_WIDTH', 1024},...
	{'SCREEN_HEIGHT', 768},...
	{'VIEWING_DISTANCE', 57.3},...
	{'DOTS_PER_CENTIMETER_H', 24.26},...
	{'DOTS_PER_CENTIMETER_V', 24.26},...
	{'SACCADE_VELOCITY_THRESHOLD', 20.0},...
	{'SACCADE_ACCELERATION_THRESHOLD', 3800.0},...
	{'SACCADE_MINIMUM_DURATION', 12},...
	{'SACCADE_MINIMUM_AMPLITUDE', 0.2},...
	{'FIXATION_MINIMUM_DURATION', 12},...
	{'BLINK_MINIMUM_DURATION', 50},...
	{'RESAMPLING', 0},...
	{'FILTER_TYPE', 'identity'},...
	{'FILTER_WN', 0.2},...
	{'FILTER_SIZE', 5},...
	{'FILTER_ORDER', 3}
};

try

	%-----------------------------------------------------------------
	% Open PsychToolbox Window.
	%   wptr and wrect are necessary to initialize SimpleGazeTracker
	%   toolbox later.
	%-----------------------------------------------------------------
	%[wptr, wrect] = Screen('OpenWindow',0,[0,0,0],[0,0,1024,768]);
	[wptr, wrect] = Screen('OpenWindow',0);
	cx = wrect(3)/2;
	cy = wrect(4)/2;
	
	%-----------------------------------------------------------------
	% Initialize SimpleGazeTracker.
	%   Return value of SimpleGazeTracker is necessary to customize
	%   parameters later.
	%-----------------------------------------------------------------
	param = SimpleGazeTracker('Initialize',wptr,wrect);
	
	%-----------------------------------------------------------------
	% Update SimpleGazeTracker Toolbox parameters.
	%-----------------------------------------------------------------
	%'localhost' means that SimpleGazeTracker is running on the same PC.
	param.IPAddress = ipAddress;
	param.calArea = wrect;
	param.calTargetPos = [0,0;-400,-300; 0,-300; 400,-300;...
	                          -400,   0; 0,   0; 400,   0;...
	                          -400, 300; 0, 300; 400, 300];
	for i=1:length(param.calTargetPos)
		param.calTargetPos(i,:) = param.calTargetPos(i,:)+[cx,cy];
	end
	result = SimpleGazeTracker('UpdateParameters',param);
	if result{1} < 0 %failed
		disp('Could not update parameter. Abort.');
		Screen('CloseAll');
		return;
	end
	
	%-----------------------------------------------------------------
	% Connect to SimpleGazeTracker and open data file.
	%-----------------------------------------------------------------
	
	res = SimpleGazeTracker('Connect');
	
	if res==-1 %connection failed
		Screen('CloseAll');
		return;
	end
	
	SimpleGazeTracker('OpenDataFile',[logfilename, '.csv'],0); %datafile is not overwritten.

	%
	% Update Camera Image Buffer
	%
	
	imgsize = SimpleGazeTracker('GetCameraImageSize');
	param.imageWidth = imgsize(1);
	param.imageHeight = imgsize(2);
	result = SimpleGazeTracker('UpdateParameters',param);
	if result{1} < 0 %failed
		disp('Could not update parameter. Abort.');
		Screen('CloseAll');
		return;
	end
	
	%
	% Send settings
	%
	res = SimpleGazeTracker('SendSettings', settings);
	
	%-----------------------------------------------------------------
	% Perform calibration.
	%-----------------------------------------------------------------
	while 1
		res = SimpleGazeTracker('CalibrationLoop');
		if res{1}=='q'
			%Quit if calibrationloop is finished by 'q' key.
			SimpleGazeTracker('CloseConnection');
			Screen('CloseAll');
			return;
		end
		if strcmp(res{1},'ESCAPE') && res{2}==1
			%Leave from loop if calibration has been performed (res{2}==1).
			break; 
		end
    end
    
    
	fid = fopen([logfilename, '.txt'],'wt');    
    for block = 0:4
        nRectDraw = 2^(2*block);
        
        %-----------------------------------------------------------------
        % Recording.
        %   If space key is pressed, a message 'Space' is inserted to the
        %   data file and latest 6 samples of gaze position is transferred
        %   from SimpleGazeTracker.
        %   Current gaze position is transferred every frame and a white
        %   square is drawn at the current gaze position.
        %-----------------------------------------------------------------
        gazeposlist = {};
        geteyeposdelaylist = [];
        flipdelaylist = [];
        previousKeyPressTime = GetSecs();
        targetColor = 255;
        %Start recording.
        SimpleGazeTracker('StartRecording',['nRectDraw:', num2str(nRectDraw)],0.1);
        
        fst = GetSecs();
        for q = 1:360 %360 frames
            [keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
            if keyCode(KbName('Space'))==1
                % prevent chattering...
                if GetSecs()-previousKeyPressTime > 0.2
                    SimpleGazeTracker('SendMessage','Space');
                    %get the latest 6 samples.
                    tmp = SimpleGazeTracker('GetEyePositionList',6,0,0.02);
                    if ~isempty(tmp)
                        gazeposlist(length(gazeposlist)+1) = {tmp};
                    end
                    %update previousKeyPressTime
                    previousKeyPressTime = GetSecs();
                    %change target color
                    if targetColor==255
                        targetColor=0;
                    else
                        targetColor=255;
                    end
                end
            end
            if mod(q,60)==0
                %Send message every 60 frames.
                SimpleGazeTracker('SendMessage',num2str(q));
            end
            
            st = GetSecs();
            %get current gaze position (moving average of 3 samples).
            pos = SimpleGazeTracker('GetEyePosition',3,0.02);
            geteyeposdelaylist = [geteyeposdelaylist, 1000*(GetSecs()-st)];
            
            stimx = 200*cos(q/180*pi)+cx;
            stimy = 200*sin(q/180*pi)+cy;
            %horizontal component of current gaze position
            markerx = pos{1}(1);
            %vertical component of current gaze position
            markery = pos{1}(2);
            for nn = 1:nRectDraw
                Screen('FillRect',wptr,127);
            end
            Screen('FillRect',wptr,0,[stimx-5,stimy-5,stimx+5,stimy+5]);
            %draw marker at the current gaze position.
            Screen('FillRect',wptr,targetColor,[markerx-5,markery-5,markerx+5,markery+5]);
            Screen('Flip',wptr);
            flipdelaylist = [flipdelaylist, 1000*(GetSecs()-fst)];
            fst = GetSecs();
        end
        %Stop recording.
        SimpleGazeTracker('StopRecording','',0.1);
        
        %-----------------------------------------------------------------
        % Clear Screen
        %-----------------------------------------------------------------
        Screen('FillRect',wptr,127);
        Screen('Flip',wptr);
        
        %-----------------------------------------------------------------
        % Output
        %-----------------------------------------------------------------
        
        %Output delay of SimpleGazeTracker('GetEyePosition')
        fprintf(fid,['nRectDraw:',num2str(nRectDraw),'\n']);
        fprintf(fid,'Delay of SimpleGazeTracker(''GetEyePosition'')\n');
        for i=1:length(geteyeposdelaylist)
            fprintf(fid,'%f\n',geteyeposdelaylist(i));
        end
        
        %Output delay of Screen('Flip')
        fprintf(fid,'Delay of Screen(''Flip'')\n');
        for i=1:length(flipdelaylist)
            fprintf(fid,'%f\n',flipdelaylist(i));
        end
        
        fprintf(fid,'\n');    
    end

    fclose(fid);
    

	%-----------------------------------------------------------------
	% Close remote data file and network connection.
	%-----------------------------------------------------------------
	SimpleGazeTracker('CloseDataFile');
	SimpleGazeTracker('CloseConnection');
	
	%-----------------------------------------------------------------
	% Close Psychtoolbox screen.
	%-----------------------------------------------------------------
	Screen('CloseAll');

catch
	SimpleGazeTracker('CloseConnection');
	Screen('CloseAll');
	psychrethrow(psychlasterror);
end
