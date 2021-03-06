%Screen('Preference','SkipSyncTests',1);
AssertOpenGL;

ipAddress = input('SimpleGazeTracker address: ','s');

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
	
	SimpleGazeTracker('OpenDataFile','data.csv',0); %datafile is not overwritten.

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
	previousKeyPressTime = GetSecs();
	targetColor = 255;
	%Start recording.
	SimpleGazeTracker('StartRecording','Test trial',0.1);

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
		Screen('FillRect',wptr,127);
		Screen('FillRect',wptr,0,[stimx-5,stimy-5,stimx+5,stimy+5]);
		%draw marker at the current gaze position.
		Screen('FillRect',wptr,targetColor,[markerx-5,markery-5,markerx+5,markery+5]);
		Screen('Flip',wptr);
	end
	%Stop recording.
	SimpleGazeTracker('StopRecording','',0.1);
	
	%-----------------------------------------------------------------
	% Clear Screen
	%-----------------------------------------------------------------
	Screen('FillRect',wptr,127);
	Screen('Flip',wptr);
	
	%-----------------------------------------------------------------
	% Transfer data from SimpleGazeTracker.
	%-----------------------------------------------------------------
	fid = fopen('log.txt','wt');
	%Get all messages.
	msglist = SimpleGazeTracker('GetWholeMessageList',3.0);
	fprintf(fid,'GetWholeMessageList test\n');
	for i=1:length(msglist)
		fprintf(fid,'%f,%s\n',msglist{i,1},msglist{i,2});
	end
	fprintf(fid,'\n');
	
	%Get all gaze position data.
	wholegazeposlist = SimpleGazeTracker('GetWholeEyePositionList',1,3.0);
	fprintf(fid,'GetWholeEyePositionList test\n');
	for i=1:length(wholegazeposlist)
		fprintf(fid,'%f,%.1f,%.1f\n',...
			wholegazeposlist(i,1),wholegazeposlist(i,2),wholegazeposlist(i,3));
	end
	fprintf(fid,'\n');
	
	%Output result of GetEyePositionList
	fprintf(fid,'GetEyePositionList test\n');
	fprintf(fid,'Number of space-key press:%d\n',length(gazeposlist));
	for i=1:length(gazeposlist)
		fprintf(fid,'Keypress %d\n',i);
		for j=1:length(gazeposlist{i})
			fprintf(fid,'%f,%.1f,%.1f\n',...
				gazeposlist{i}(j,1),gazeposlist{i}(j,2),gazeposlist{i}(j,3));
		end
	end
	fprintf(fid,'\n');
	
	%Output delay of SimpleGazeTracker('GetEyePosition')
	fprintf(fid,'Delay of SimpleGazeTracker(''GetEyePosition'')\n');
	for i=1:length(geteyeposdelaylist)
		fprintf(fid,'%f\n',geteyeposdelaylist(i));
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
