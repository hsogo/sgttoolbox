%AssertOpenGL;

try

	[wptr, wrect] = Screen('OpenWindow',0,[0,0,0],[0,0,1024,768])
	%[wptr, wrect] = Screen('OpenWindow',0)
	cx = wrect(3)/2;
	cy = wrect(4)/2;

	param = SimpleGazeTracker('Initialize',wptr,wrect);
	param.IPAddress = 'localhost';
	param.imageWidth = 640;
	param.imageHeight = 480;
	param.calArea = wrect;
	param.calTargetPos = [0,0;-400,-300; 0,-300; 400,-300;\
	                          -400,   0; 0,   0; 400,   0;\
	                          -400, 300; 0, 300; 400, 300];
	for i=1:length(param.calTargetPos)
		param.calTargetPos(i,:) = param.calTargetPos(i,:)+[cx,cy];
	end
	param = SimpleGazeTracker('UpdateParameters',param);
	SimpleGazeTracker('Connect');
	SimpleGazeTracker('OpenDataFile','data.csv',0);
	while 1
		res = SimpleGazeTracker('CalibrationLoop');
		if res{1}=='q'
			SimpleGazeTracker('CloseConnection');
			Screen('CloseAll');
			return;
		end
		if res{1}=='ESCAPE' && res{2}==1
			break;
		end
	end
	
	gazeposlist = {};
	SimpleGazeTracker('StartRecording','Test trial',0.1);
	for q = 1:300
		[keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
		if keyCode(KbName('Space'))==1
			SimpleGazeTracker('SendMessage','Space');
			tmp = SimpleGazeTracker('GetEyePositionList',-6,0,0.02);
			if length(tmp)>0
				gazeposlist(length(gazeposlist)+1) = tmp;
			end
		end
		%if mod(q,60)==0
		%	SimpleGazeTracker('SendMessage',num2str(q));
		%end
		st = GetSecs();
		pos = SimpleGazeTracker('GetEyePosition',6);
		1000*(GetSecs()-st);
		stimx = 200*cos(q/50)+cx;
		stimy = 200*sin(q/50)+cy;
		markerx = pos{1}(1);
		markery = pos{1}(2);
		Screen('FillRect',wptr,127);
		Screen('FillRect',wptr,0,[stimx-5,stimy-5,stimx+5,stimy+5]);
		Screen('FillRect',wptr,255,[markerx-5,markery-5,markerx+5,markery+5]);
		Screen('Flip',wptr);
	end
	SimpleGazeTracker('StopRecording','',0.1);
	fid = fopen('log.txt','wt');
	msglist = SimpleGazeTracker('GetWholeMessageList',1.0);
	fprintf(fid,'GetWholeMessageList test\n');
	for i=1:length(msglist)
		fprintf(fid,'%f,%s\n',msglist{i,1},msglist{i,2});
	end
	fclose(fid);
	wholegazeposlist = SimpleGazeTracker('GetWholeEyePositionList',1,1.0);
	
	SimpleGazeTracker('CloseDataFile');
	SimpleGazeTracker('CloseConnection');

	Screen('CloseAll');
catch
	SimpleGazeTracker('CloseConnection');
	Screen('CloseAll');
	psychrethrow(psychlasterror);
end

