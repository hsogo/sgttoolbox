AssertOpenGL;

ipAddress = input('SimpleGazeTracker address: ','s');
imageWidth = input('Camera image width: ');
imageHeight = input('Camera image height ');


%try

	%-----------------------------------------------------------------
	% Open PsychToolbox Window.
	%   wptr and wrect are necessary to initialize SimpleGazeTracker
	%   toolbox later.
	%-----------------------------------------------------------------
	%[wptr, wrect] = Screen('OpenWindow',0)
	
	[wptr, wrect] = Screen('OpenWindow',0,[0,0,0],[0,0,1024,768])
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
	param.imageWidth = imageWidth;
	param.imageHeight = imageHeight;
	param.calArea = wrect;
	param.calTargetPos = [0,0;-400,-300; 0,-300; 400,-300;\
	                          -400,   0; 0,   0; 400,   0;\
	                          -400, 300; 0, 300; 400, 300];
	for i=1:length(param.calTargetPos)
		param.calTargetPos(i,:) = param.calTargetPos(i,:)+[cx,cy];
	end
	param = SimpleGazeTracker('UpdateParameters',param);
	
	%-----------------------------------------------------------------
	% Connect to SimpleGazeTracker and open data file.
	%-----------------------------------------------------------------
	res = SimpleGazeTracker('Connect');
	if res==-1 %connection failed
		Screen('CloseAll');
		quit
	end
	SimpleGazeTracker('OpenDataFile','data.csv',0); %datafile is not overwritten.
	
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
		if res{1}=='ESCAPE' && res{2}==1
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
	%Start recording.
	SimpleGazeTracker('StartRecording','Test trial',0.1);
	WaitSecs(0.5);

	for q = 1:300 %300 frames
		[keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
		if keyCode(KbName('Space'))==1
			GetSecs()-previousKeyPressTime
		    if GetSecs()-previousKeyPressTime > 0.1
				SimpleGazeTracker('SendMessage','Space');
				%get the latest 6 samples.
				tmp = SimpleGazeTracker('GetEyePositionList',6,0,0.5);
				if length(tmp)>0
					gazeposlist(length(gazeposlist)+1) = tmp;
				end
				%update previousKeyPressTime
				previousKeyPressTime = GetSecs();
		    end
		end
		if mod(q,60)==0
			%Send message every 60 frames.
			SimpleGazeTracker('SendMessage',num2str(q));
		end
		
		st = GetSecs();
		%get current gaze position (moving average of 3 samples).
		pos = SimpleGazeTracker('GetEyePosition',3,0.5);
		geteyeposdelaylist = [geteyeposdelaylist, 1000*(GetSecs()-st)];
		
		stimx = 200*cos(q/50)+cx;
		stimy = 200*sin(q/50)+cy;
		%horizontal component of current gaze position
		markerx = pos{1}(1);
		%vertical component of current gaze position
		markery = pos{1}(2);
		Screen('FillRect',wptr,127);
		Screen('FillRect',wptr,0,[stimx-5,stimy-5,stimx+5,stimy+5]);
		%draw marker at the current gaze position.
		Screen('FillRect',wptr,255,[markerx-5,markery-5,markerx+5,markery+5]);
		Screen('Flip',wptr);
	end
	%Stop recording.
	SimpleGazeTracker('StopRecording','',0.1);
	WaitSecs(0.5);
	
	%-----------------------------------------------------------------
	% Transfer data from SimpleGazeTracker.
	%-----------------------------------------------------------------
	fid = fopen('log.txt','wt');
	%Get all messages.
	msglist = SimpleGazeTracker('GetWholeMessageList',1.0);
	fprintf(fid,'GetWholeMessageList test\n');
	for i=1:length(msglist)
		fprintf(fid,'%f,%s\n',msglist{i,1},msglist{i,2});
	end
	fprintf(fid,'\n');
	WaitSecs(0.5);
	
	%Get all gaze position data.
	wholegazeposlist = SimpleGazeTracker('GetWholeEyePositionList',1,1.0);
	fprintf(fid,'GetWholeEyePositionList test\n');
	for i=1:length(wholegazeposlist)
		fprintf(fid,'%f,%.1f,%.1f\n',\
			wholegazeposlist(i,1),wholegazeposlist(i,2),wholegazeposlist(i,3));
	end
	fprintf(fid,'\n');
	WaitSecs(0.5);
	
	%Output result of GetEyePositionList
	fprintf(fid,'GetEyePositionList test\n');
	fprintf(fid,'Number of space-key press:%d\n',length(gazeposlist));
	for i=1:length(gazeposlist)
		fprintf(fid,'Keypress %d\n',i);
		for j=1:length(gazeposlist{i})
			fprintf(fid,'%f,%.1f,%.1f\n',\
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
%catch
%	SimpleGazeTracker('CloseConnection');
%	Screen('CloseAll');
%	psychrethrow(psychlasterror);
%end
