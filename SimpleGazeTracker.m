function ret = SimpleGazeTracker(varargin)
% SimpeGazeTracker toolbox 0.2.2 (compatible with SimpleGazeTracker 0.6.5)
% Copyright (C) 2012-2013 Hiroyuki Sogo.
% Thanks to Ryuta Iseki and Yuta Kawabe for Matlab support.
% 
% Distributed under the terms of the GNU General Public License (GPL).
% 
% Usage:
% 
% ===== Initialize SimpleGazeTracker toolbox =====
% %Initialize SimpleGazeTracker toolbox parameters
% param = SimpleGazeTracker('Initialize', wptr, wrect);
% 
% %Update SimpleGazeTracker toolbox parameters
% ret = SimpleGazeTracker('UpdateParameters',param);
% 
% ===== Open/close connection with SimpleGazeTracker =====
% %Open TCP/IP connection with SimpleGazeTracker
% ret = SimpleGazeTracker('Connect');
% 
% %Close TCP/IP connection
% ret = SimpleGazeTracker('CloseConnection');
% 
% ===== Open/close data file =====
% %Open data file on SimpleGazeTracker
% ret = SimpleGazeTracker('OpenDataFile', filename, overwrite);
% 
% %Close data file on SimpleGazeTracker
% ret = SimpleGazeTracker('CloseDataFile');
% 
% ===== Calibration =====
% %Start Calibration procedure
% res = SimpleGazeTracker('CalibrationLoop');
% 
% ===== Start/stop recording =====
% %Start recording
% ret = SimpleGazeTracker('StartRecording', message, wait);
% 
% %Stop recording
% ret = SimpleGazeTracker('StopRecording', message, wait);
% 
% ===== Commands during recording =====
% %Insert message into data file
% ret = SimpleGazeTracker('SendMessage', message);
% 
% %Get latest gaze position
% pos = SimpleGazeTracker('GetEyePosition', ma, timeout);
%	
% %Get latest gaze position list.
% msg = SimpleGazeTracker('GetEyePositionList', n, getPupil, timeout)
% 
% ===== Commands immediately after recording =====
% %Get all messages inserted in the latest recording.
% msg = SimpleGazeTracker('GetWholeMessageList', timeout)
% 
% %Get all gaze positions recorded in the latest recording.
% msg = SimpleGazeTracker('GetWholeEyePositionList', getPupil, timeout)
%
% ===== Off-line data analysis =====
% %Read SimpleGazeTracker CSV file.
% data = SimpleGazeTracker('ReadDataFile', filename)
%

persistent sgttbx_param;
persistent sgttbx_sockets;

ret = -1;
switch(varargin{1})
	case 'Initialize'
		if nargin == 1
			disp('Window must be specified.')
			return;
		end
		ret = sgttbx_initialize(varargin);
		sgttbx_param = ret;
		return;
	case 'UpdateParameters'
		isvalid = sgttbx_verifyparam(varargin{2});
		if isvalid>=0
			sgttbx_param = varargin{2};
		end
		ret = {isvalid, sgttbx_param};
		return;
	case 'OpenDataFile'
		ret = sgttbx_openDataFile(sgttbx_sockets, varargin{2}, varargin{3});
		return;
	case 'CloseDataFile'
		ret = sgttbx_closeDataFile(sgttbx_sockets);
		return;
	case 'Connect'
		sgttbx_net('closeall')
		res = sgttbx_connect(sgttbx_param);
		if isstruct(res)
			sgttbx_sockets = res;
			ret = 0;
			return;
		else
			return;
		end
	case 'CloseConnection'
		sgttbx_net('closeall');
		ret = 0;
		return;
	case 'SendMessage'
		ret = sgttbx_sendMessage(sgttbx_sockets, varargin{2});
		return;
	case 'SendSettings'
		disp('SendSettings is not implemented.')
	case 'CalibrationLoop'
		ret = sgttbx_calibrationLoop(sgttbx_param, sgttbx_sockets);
		return;
	case 'StartRecording'
		ret = sgttbx_startRecording(sgttbx_sockets, varargin{2}, varargin{3});
		return;
	case 'StopRecording'
		ret = sgttbx_stopRecording(sgttbx_sockets, varargin{2}, varargin{3});
		return;
	case 'SendCommand'
		ret = sgttbx_sendCommand(sgttbx_sockets, varargin{2});
		return;
	case 'GetEyePosition'
		ret = sgttbx_getEyePosition(sgttbx_sockets, varargin{2}, varargin{3});
		return;
	case 'GetEyePositionList'
		ret = sgttbx_getEyePositionList(sgttbx_sockets, varargin{2}, varargin{3}, varargin{4});
		return;
	case 'GetWholeEyePositionList'
		ret = sgttbx_getWholeEyePositionList(sgttbx_sockets, varargin{2}, varargin{3});
		return;
	case 'GetWholeMessageList'
		ret = sgttbx_getWholeMessageList(sgttbx_sockets, varargin{2});
		return;
	case 'ReadDataFile'
		ret = sgttbx_readDataFile(varargin{2});
	otherwise
		disp(['Invalid command. (', varargin{1}, ')'])
end

function param = sgttbx_initialize(arg)
	param.wptr = arg{2};
	param.wrect = arg{3};
	param.IPAddress = '192.168.1.1';
	param.sendPort = 10000;
	param.recvPort = 10001;
	param.imageWidth = 320;
	param.imageHeight = 240;
	param.previewWidth = 640;
	param.previewHeight = 480;
	param.validationShift = 20;
	param.showCalDisplay = 1;
	param.numSamplesPerTrgpos = 10;
	param.caltargetMotionDuration = 1.0;
	param.caltargetDurationPerPos = 2.0;
	param.calGetSampleDelay = 0.4;
	param.calArea = arg{3};
	cx = (param.wrect(3)-param.wrect(1))/2;
	cy = (param.wrect(4)-param.wrect(2))/2;
	param.calTargetPos = [ cx, cy;
				cx-350,cy-250; cx-350,cy; cx-350,cy+250;
				cx    ,cy-250; cx    ,cy; cx    ,cy+250;
				cx+350,cy-250; cx+350,cy; cx+350,cy+250];

	sgttbx_param = param;


function res = sgttbx_connect(sgttbx_param)
	res = -1;
	if ~isstruct(sgttbx_param)
		disp('Parameters may not be initialized.')
		return;
	end
	sendcon = sgttbx_net('tcpconnect',sgttbx_param.IPAddress,sgttbx_param.sendPort, 'noblock');
	if sendcon < 0
		disp('tcpconnect was Failed.')
		return;
	end
	recvsock = sgttbx_net('tcpsocket',sgttbx_param.recvPort);
	if recvsock < 0
		disp('tcpsocket was Failed')
		return;
	end
	startTime = GetSecs();
	while GetSecs()-startTime<5
		recvcon = sgttbx_net(recvsock, 'tcplisten');
		if recvcon>=0
			break;
		end
		WaitSecs(0.5);
	end
	if recvcon < 0
		disp('tcplisten Failed')
		return;
	end
	sgttbx_net(recvcon,'setreadtimeout',1.0);
	[ip,port] = sgttbx_net(recvcon, 'gethost');
	disp(['Connected from ', num2str(ip(1)), '.', num2str(ip(2)), '.', num2str(ip(3)), '.', num2str(ip(4)), ':', num2str(port)])

	sockets.recvsock = recvsock;
	sockets.sendcon = sendcon;
	sockets.recvcon = recvcon;
	res = sockets;
	return; 

function res = sgttbx_verifyparam(newparam)
	res = -1;
	if ~(isnumeric(newparam.wrect) && length(newparam.wrect)==4)
		disp('calArea must be an array of four numbers.')
		return;
	end
	if ~ischar(newparam.IPAddress)
		disp('IP address must be a string.')
		return;
	end
	if ~(isnumeric(newparam.sendPort) && newparam.sendPort>0)
		disp('sendPort must be a positive integer.')
		return;
	end
	if ~(isnumeric(newparam.recvPort) && newparam.recvPort>0)
		disp('recvPort must be a positive integer.')
		return;
	end
	if ~(isnumeric(newparam.imageWidth) && newparam.imageWidth>0)
		disp('imageWidth must be a positive integer.')
		return;
	end
	if ~(isnumeric(newparam.imageHeight) && newparam.imageHeight>0)
		disp('imageHeight must be a positive integer.')
		return;
	end
	if ~(isnumeric(newparam.previewWidth) && newparam.previewWidth>0)
		disp('previewWidth must be a positive integer.')
		return;
	end
	if ~(isnumeric(newparam.previewHeight) && newparam.previewHeight>0)
		disp('previewHeight must be a positive integer.')
		return;
	end
	if ~(isfloat(newparam.validationShift) && newparam.validationShift>=0)
		disp('validationShift must be zero or a positive number.')
		return;
	end
	if ~(newparam.showCalDisplay==0 || newparam.showCalDisplay==1)
		disp('showCalDisplay must be 0 or 1.')
		return;
	end
	if ~(isnumeric(newparam.numSamplesPerTrgpos) && newparam.numSamplesPerTrgpos>0)
		disp('numSamplesPerTrgpos must be a positive integer.')
		return;
	end
	if ~(isfloat(newparam.caltargetMotionDuration) && newparam.caltargetMotionDuration>=0)
		disp('caltargetMotionDuration must be zero or a positive number.')
		return;
	end
	if ~(isfloat(newparam.caltargetDurationPerPos) && newparam.caltargetDurationPerPos>0)
		disp('caltargetDurationPerPos must be a positive number.')
		return;
	end
	if ~(isfloat(newparam.calGetSampleDelay) && newparam.calGetSampleDelay>=0)
		disp('calGetSampleDelay must be zero or a positive number.')
		return;
	end
	if newparam.caltargetDurationPerPos < newparam.caltargetMotionDuration + newparam.calGetSampleDelay
		disp('caltargetDurationPerPos must be greater than newparam.caltargetMotionDuration + newparam.calGetSampleDelay.')
		return;
	end
	if ~(isnumeric(newparam.calArea) && length(newparam.calArea)==4)
		disp('calArea must be an array of four numbers.')
		return;
	end
	for i=1:length(newparam.calTargetPos)
		if ~(isnumeric(newparam.calTargetPos) && length(newparam.calTargetPos(i,:))==2)
			disp('calTargetPos must be a numeric array of Nx2.')
			return;
		end
	end
	res = 0;

function res = sgttbx_openDataFile(sockets, fname, overwrite)
	if ~(overwrite==1 || overwrite==0)
		res = -1;
		return;
	end
	command = ['openDataFile',0,fname,0,num2str(overwrite)];
	res = sgttbx_sendCommand(sockets, command);

function res = sgttbx_closeDataFile(sockets)
	res = sgttbx_sendCommand(sockets, 'closeDataFile');

function res = sgttbx_sendCommand(sockets, command)
	res = -1;
	if ~isstruct(sockets)
		return;
	end
	if sockets.sendcon < 0
		return;
	end
	if sgttbx_net(sockets.sendcon,'status') == 0
		return;
	end
	%fdisp(stderr,command);
	command(end+1) = 0;
	%start = GetSecs();
	sgttbx_net(sockets.sendcon, 'write', command);
	%fdisp(stderr,1000*(GetSecs()-start));
	res = 0;

function res = sgttbx_sendMessage(sockets, message)
	res = sgttbx_sendCommand(sockets, ['insertMessage',0,message]);

function msg = sgttbx_getCurrentMenu(sockets)
	msg = '';
	if ~isstruct(sockets)
		return
	end
	sgttbx_sendCommand(sockets, 'getCurrMenu');
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			msg = data(1:term(1)-1);
			return;
		else
			msg = [msg, data];
		end
		
		if GetSecs()-startTime > 0.1 %timeout
			return
		end
	end

function img = sgttbx_getCameraImage(param, sockets)
	img = [];
	if ~isstruct(sockets)
		return
	end
	sgttbx_sendCommand(sockets, 'getImageData');
	while 1
		data = sgttbx_net(sockets.recvcon, 'read', 'uint8');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			img = [img, data(1:term(1)-1)];
			break;
		else
			img = [img, data];
		end
	end

	expectedSize = param.imageWidth*param.imageHeight;
	
	if length(img) < expectedSize
		img = [img, zeros(1,expectedSize-length(img),'uint8')];
	elseif length(img) > expectedSize
		img = img(1:expectedSize);
	end
	
	img = transpose(reshape(uint8(img),param.imageWidth,param.imageHeight));

function res = sgttbx_calibrationLoop(param, sockets)
	res = {'q',0};
	calmsgstr = 'No calibration results';
	if ~isstruct(param)
		disp('No parameter.')
		return;
	end
	if ~isstruct(sockets)
		disp('No sockets.')
		return;
	end
	KbName('UnifyKeyNames');
	Screen('TextSize',param.wptr, 24);
	Screen('TextStyle', param.wptr, 0);
	msgstr = sgttbx_getCurrentMenu(sockets);
	showCameraImage = 0;
	showCalResults = 0;
	isCalDone = 0;
	calimgtex = -1;
	
	while 1
		[keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
		if keyCode(KbName('RightArrow'))==1
			sgttbx_sendCommand(sockets, 'key_RIGHT');
			WaitSecs(0.1);
			msgstr = sgttbx_getCurrentMenu(sockets);
		end
		if keyCode(KbName('LeftArrow'))==1
			sgttbx_sendCommand(sockets, 'key_LEFT');
			WaitSecs(0.1);
			msgstr = sgttbx_getCurrentMenu(sockets);
		end
		if keyCode(KbName('UpArrow'))==1
			sgttbx_sendCommand(sockets, 'key_UP');
			WaitSecs(0.2);
			msgstr = sgttbx_getCurrentMenu(sockets);
		end
		if keyCode(KbName('DownArrow'))==1
			sgttbx_sendCommand(sockets, 'key_DOWN');
			WaitSecs(0.2);
			msgstr = sgttbx_getCurrentMenu(sockets);
		end
		if keyCode(KbName('ESCAPE'))==1
			if calimgtex>=0
				Screen('Close', calimgtex);
			end
			res = {'ESCAPE',isCalDone};
			return;
		end
		if keyCode(KbName('q'))==1
			sgttbx_sendCommand(sockets, 'key_Q');
			if calimgtex>=0
				Screen('Close', calimgtex);
			end
			res = {'q',isCalDone};
			return;
		end
		if keyCode(KbName('z'))==1
			if showCameraImage == 1
				showCameraImage = 0;
			else
				showCameraImage = 1;
			end
			WaitSecs(0.5);
		end
		if keyCode(KbName('x'))==1
			if showCalResults == 1
				showCalResults = 0;
				sgttbx_sendCommand(sockets,['toggleCalResult',0,'0']);
			else
				showCalResults = 1;
				sgttbx_sendCommand(sockets,['toggleCalResult',0,'1']);
			end
			WaitSecs(0.5);
		end
		if keyCode(KbName('c'))==1
			sgttbx_doCalibration(param, sockets);
			calmsgstr = sgttbx_getCalResults(sockets, 0.2);
			calimgtex = sgttbx_drawCalResults(param, sockets, calimgtex, 0.2);
			isCalDone = 1;
			showCalResults = 1;
		end
		if keyCode(KbName('v'))==1
			if(isCalDone==1)
				sgttbx_doValidation(param, sockets);
				calmsgstr = sgttbx_getCalResults(sockets, 0.2);
				calimgtex = sgttbx_drawCalResults(param, sockets, calimgtex, 0.2);
				showCalResults = 1;
			end
		end
		
		Screen('FillRect',param.wptr,127);
		if showCalResults==1
			if isCalDone
				Screen('DrawTexture',param.wptr,calimgtex);
			else
				Screen('FillRect',param.wptr,0);
			end	
			Screen('DrawText',param.wptr,calmsgstr,(param.wrect(3)-param.imageWidth)/2,...
				(param.wrect(4)+param.imageHeight)/2+10,[255, 255, 255, 255]);
		else
			if showCameraImage==1
				img = sgttbx_getCameraImage(param, sockets);
				imgtex = Screen('MakeTexture', param.wptr, img);
				Screen('DrawTexture', param.wptr, imgtex);
				Screen('Close',imgtex);
			end
			Screen('DrawText',param.wptr,msgstr,(param.wrect(3)-param.imageWidth)/2,...
				(param.wrect(4)+param.imageHeight)/2+10,[255, 255, 255, 255]);
		end
		Screen('Flip', param.wptr);
	end

function res = sgttbx_startRecording(sockets, message, wait)
	res = sgttbx_sendCommand(sockets,['startRecording',0,message]);
	WaitSecs(wait);

function res = sgttbx_stopRecording(sockets, message, wait)
	res = sgttbx_sendCommand(sockets,['stopRecording',0,message]);
	WaitSecs(wait);
	
function pos = sgttbx_getEyePosition(sockets, n, timeout)
	pos = {[-10000,-10000],0};
	sgttbx_sendCommand(sockets, ['getEyePosition',0,num2str(n)]);
	result = [];
	startTime = GetSecs();
	
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result; data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime > timeout
			return
		end
	end
	
	if ~isempty(result)
		resnum = str2num(result);
		if length(resnum)==3
			pos{1} = resnum(1:2);
			pos{2} = resnum(3);
		end
	end

function res = isBinocularMode(sockets)
	sgttbx_sendCommand(sockets, 'isBinocularMode');
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			msg = data(1:term(1)-1);
			if msg(1)=='1'
				res = 1;
			else
				res = 0;
			end
			return;
		end
	end

function res = sgttbx_doCalibration(param, sockets)
	res = sgttbx_sendCommand(sockets, ['startCal',0,...
		num2str(param.calArea(1)),',',...
		num2str(param.calArea(2)),',',...
		num2str(param.calArea(3)),',',...
		num2str(param.calArea(4))]);
	if res<0
		return
	end
	
	while 1
		index = randperm(length(param.calTargetPos)-1)+1;
		if param.calTargetPos(index(1),1) ~= param.calTargetPos(1,1) || param.calTargetPos(index(1),2) ~= param.calTargetPos(1,2)
			break;
		end
	end
	index = [1, index];
	calCheckList = zeros(1,length(param.calTargetPos));	
	
	cx = param.calTargetPos(1,1);
	cy = param.calTargetPos(1,2);
	Screen('FillRect',param.wptr,127);
	Screen('FillRect',param.wptr,0,[cx-5,cy-5,cx+5,cy+5]);
	Screen('Flip',param.wptr);
	
	while 1
		[keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
		[x,y,b,f,v,vi]=GetMouse(param.wptr);
		if keyCode(KbName('Space'))==1 || b(1)==1
			break;
		end
		WaitSecs(0.2);
	end
	
	startTime = GetSecs();
	while 1
		currentTime = GetSecs()-startTime;
		t = mod(currentTime, param.caltargetDurationPerPos);
		prevTargetPosition = floor((currentTime-t)/param.caltargetDurationPerPos)+1; %Indics starts 1 in Matlab/octave
		currentTargetPosition = prevTargetPosition+1;
		if currentTargetPosition > length(param.calTargetPos)
			break
		end
		
		if t<param.caltargetMotionDuration
			p1 = t/param.caltargetMotionDuration;
			p2 = 1.0-t/param.caltargetMotionDuration;
			cx = p1*param.calTargetPos(index(currentTargetPosition),1) + ...
				p2*param.calTargetPos(index(prevTargetPosition),1);
			cy = p1*param.calTargetPos(index(currentTargetPosition),2) + ...
				p2*param.calTargetPos(index(prevTargetPosition),2);
		else
			cx = param.calTargetPos(index(currentTargetPosition),1);
			cy = param.calTargetPos(index(currentTargetPosition),2);
		end
		
		if calCheckList(prevTargetPosition)==0 && t>param.caltargetMotionDuration+param.calGetSampleDelay
			sgttbx_sendCommand(sockets, ['getCalSample',0,...
				num2str(param.calTargetPos(index(currentTargetPosition),1)),',',...
				num2str(param.calTargetPos(index(currentTargetPosition),2)),',',...
				num2str(param.numSamplesPerTrgpos),0]);
			calCheckList(prevTargetPosition) = 1;
		end
		
		Screen('FillRect',param.wptr,127);
		Screen('FillRect',param.wptr,0,[cx-5,cy-5,cx+5,cy+5]);
		Screen('Flip',param.wptr);
	end
	
	sgttbx_sendCommand(sockets,'endCal');

function res = sgttbx_doValidation(param, sockets)
	res = sgttbx_sendCommand(sockets, ['startVal',0,...
		num2str(param.calArea(1)),',',...
		num2str(param.calArea(2)),',',...
		num2str(param.calArea(3)),',',...
		num2str(param.calArea(4))]);
	if res<0
		return
	end
	
	valTargetPos = zeros(size(param.calTargetPos));
	valTargetPos(1,:) = param.calTargetPos(1,:);
	for i=2:length(param.calTargetPos) % don't modify first element
		valTargetPos(i,1) = param.calTargetPos(i,1) + 2*(mod(floor(rand()*10),2)-0.5) * param.validationShift;
		valTargetPos(i,2) = param.calTargetPos(i,2) + 2*(mod(floor(rand()*10),2)-0.5) * param.validationShift;
	end
	
	while 1
		index = randperm(length(valTargetPos)-1)+1;
		if valTargetPos(index(1),1) ~= valTargetPos(1,1) || valTargetPos(index(1),2) ~= valTargetPos(1,2)
			break;
		end
	end
	index = [1, index];
	calCheckList = zeros(1,length(valTargetPos));	
	
	cx = valTargetPos(1,1);
	cy = valTargetPos(1,2);
	Screen('FillRect',param.wptr,127);
	Screen('FillRect',param.wptr,0,[cx-5,cy-5,cx+5,cy+5]);
	Screen('Flip',param.wptr);
	
	while 1
		[keyIsDown, secs, keyCode, deltaSecs] = KbCheck();
		[x,y,b,f,v,vi]=GetMouse(param.wptr);
		if keyCode(KbName('Space'))==1 || b(1)==1
			break;
		end
		WaitSecs(0.2);
	end
	
	startTime = GetSecs();
	while 1
		currentTime = GetSecs()-startTime;
		t = mod(currentTime, param.caltargetDurationPerPos);
		prevTargetPosition = floor((currentTime-t)/param.caltargetDurationPerPos)+1; %Indics starts 1 in Matlab/octave
		currentTargetPosition = prevTargetPosition+1;
		if currentTargetPosition > length(valTargetPos)
			break
		end
		
		if t<param.caltargetMotionDuration
			p1 = t/param.caltargetMotionDuration;
			p2 = 1.0-t/param.caltargetMotionDuration;
			cx = p1*valTargetPos(index(currentTargetPosition),1) + ...
				p2*valTargetPos(index(prevTargetPosition),1);
			cy = p1*valTargetPos(index(currentTargetPosition),2) + ...
				p2*valTargetPos(index(prevTargetPosition),2);
		else
			cx = valTargetPos(index(currentTargetPosition),1);
			cy = valTargetPos(index(currentTargetPosition),2);
		end
		
		if calCheckList(prevTargetPosition)==0 && t>param.caltargetMotionDuration+param.calGetSampleDelay
			sgttbx_sendCommand(sockets, ['getCalSample',0,...
				num2str(valTargetPos(index(currentTargetPosition),1)),',',...
				num2str(valTargetPos(index(currentTargetPosition),2)),',',...
				num2str(param.numSamplesPerTrgpos),0]);
			calCheckList(prevTargetPosition) = 1;
		end
		
		Screen('FillRect',param.wptr,127);
		Screen('FillRect',param.wptr,0,[cx-5,cy-5,cx+5,cy+5]);
		Screen('Flip',param.wptr);
	end
	
	sgttbx_sendCommand(sockets,'endVal');

function offscr = sgttbx_drawCalResults(param, sockets, calimgtex, timeout)
	sgttbx_sendCommand(sockets,'getCalResultsDetail');
	result = [];
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result, data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime>timeout
			break;
		end
	end
	if calimgtex>=0
		Screen('Close',calimgtex);
	end
	
	if ~isempty(result)
		points = str2num(result);
		[offscr, rect] = Screen('OpenOffscreenWindow', param.wptr, 127, param.wrect);
		for iter=1:length(points)/4
			Screen('DrawLine', offscr, 0, points(4*(iter-1)+1), points(4*(iter-1)+2), points(4*(iter-1)+3), points(4*iter));
		end
	end

function res = sgttbx_getCalResults(sockets, timeout)
	res = 'Calibration failed (communication error?)';
	sgttbx_sendCommand(sockets, 'getCalResults');
	result = [];
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result, data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime>timeout
			break;
		end
	end
	if ~isempty(result)
		result = str2num(result);
		if length(result)==2
			res = ['AvgError: ', num2str(result(1)), '  MaxError: ', num2str(result(2))];
		end
	end

function res = sgttbx_getWholeMessageList(sockets, timeout)
	res = {};
	sgttbx_sendCommand(sockets, 'getWholeMessageList');
	result = [];
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result, data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime>timeout
			break;
		end
	end
	
	if isempty(result) %no messages
		return;
	end
	
	%cr = find(result==0x0D);
	%lf = find(result==0x0A);
	cr = regexp(result,'\r');
	lf = regexp(result,'\n');
	if ~isempty(lf) %LF only or CR+LF
		nMsg = length(lf)+1;
		sep = [0,lf,length(result)+1];
	elseif ~isempty(cr) %CR only
		nMsg = length(cr)+1;
		sep = [0,cr,length(result)+1];
	else %single line
		nMsg = 1;
		sep = [0,length(result)+1];
	end
	
	res = cell(nMsg,2);
	nEmpty = [];
	for i=1:nMsg
		msgstr = result(sep(i)+1:sep(i+1)-1);
		c = find(msgstr==',');
		if isempty(c)
			nEmpty = [nEmpty,i];
			continue
		end
		res(i,1) = { str2num(msgstr(c(1)+1:c(2)-1)) };
		res(i,2) = { msgstr(c(2)+1:end) };
	end
	if ~isempty(nEmpty)
		for i=length(nEmpty):-1:1
			res(i,:)=[];
		end
	end

function res = sgttbx_getWholeEyePositionList(sockets, getPupil, timeout)
	res = [];
	sgttbx_sendCommand(sockets, ['getWholeEyePositionList', 0, num2str(getPupil)]);
	result = [];
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result, data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime>timeout
			break;
		end
	end
	
	if isempty(result) %no data
		return;
	end
	
	points = str2num(result);
	if getPupil==1
		res = transpose(reshape(points,4,length(points)/4)); %4=(timestamp, x, y, pupil)
	else
		res = transpose(reshape(points,3,length(points)/3)); %3=(timestamp, x, y)
	end
	
function res = sgttbx_getEyePositionList(sockets, n, getPupil, timeout)
	res = [];
	sgttbx_sendCommand(sockets, ['getEyePositionList', 0, num2str(n), 0, num2str(getPupil)]);
	result = [];
	startTime = GetSecs();
	while 1
		data = sgttbx_net(sockets.recvcon,'read');
		if isempty(data)
			continue
		end
		term = find(data==0);
		if term>=0
			result = [result, data(1:term(1)-1)];
			break;
		else
			result = [result, data];
		end
		
		if GetSecs()-startTime>timeout
			break;
		end
	end
	
	if isempty(result) %no data
		return;
	end
	
	points = str2num(result);
	if getPupil==1
		res = transpose(reshape(points,4,length(points)/4)); %4=(timestamp, x, y, pupil)
	else
		res = transpose(reshape(points,3,length(points)/3)); %3=(timestamp, x, y)
	end
	
function res = sgttbx_readDataFile(filename)
	if ~ischar(filename)
		disp('parameter must be a string')
		res = [];
		return
	end
	fp = fopen(filename,'r');
	if fp<0
		disp(['Could not oepn ', filename,'.'])
		res = [];
		return
	end
	
	DATA = [];
	
	inTrial = false;
	M = {};
	T = [];
	LHV = [];
	RHV = [];
	LP = [];
	RP = [];
	HV = [];
	P = [];
	C = [];
	PARAM = [];
	
	recordedEye = 'L';
	idxLX = 1;
	idxLY = 2;
	idxRX = 3;
	idxRY = 4;
	idxLP = -1;
	idxRP = -1;
	idxX = 1;
	idxY = 2;
	idxP = -1;
	idxC = -1;
	
	l = fgetl(fp);
	while ischar(l)
		data = sgttbx_cnv_split(l,',');
		if data{1}(1)=='#' %messages and parameters
			if strcmp(data{1},'#START_REC')
				inTrial = true;
				
				D.STARTREC = cellfun(@str2num,data(2:end));
			elseif strcmp(data{1},'#STOP_REC')
				inTrial = false;
				if recordedEye == 'B'
					D.T = T;
					D.L = LHV;
					D.R = RHV;
					D.LP = LP;
					D.RP = RP;
					D.Message = M;
				else
					if recordedEye == 'L'
						D.T = T;
						D.L = HV;
						D.R = [];
						D.LP = P;
						D.RP = [];
						D.MSG = M;
						D.C = C;
					else %recordedEye == 'R'
						D.T = T;
						D.L = [];
						D.R = HV;
						D.LP = [];
						D.RP = P;
						D.MSG = M;
						D.C = C;
					end
				end
				
				for j=1:size(PARAM,1)
					paramname = PARAM{j,1}(2:end);
					paramvalue = PARAM{j,2};
					eval(['D.PARAM.', paramname, '=paramvalue;'])
				end
				
				DATA = [DATA, D];
				M = {};
				T = [];
				LHV = [];
				RHV = [];
				LP = [];
				RP = [];
				HV = [];
				P = [];
				C = [];
				%Don't reset PARAM!
				
			elseif strcmp(data{1},'#MESSAGE')
				i = size(M,1);
				M{i+1,1} = str2num(data{2});
				M{i+1,2} = data{3};
			
			elseif strcmp(data{1},'#DATAFORMAT')
				idxLX = -1;
				idxLY = -1;
				idxRX = -1;
				idxRY = -1;
				idxLP = -1;
				idxRP = -1;
				idxX = -1;
				idxY = -1;
				idxP = -1;
				idxC = -1;
				for i=2:length(data)
					if strcmp(data{i},'T')
						idxT = i-1;
					elseif strcmp(data{i},'LX')
						idxLX = i-1;
					elseif strcmp(data{i},'LY')
						idxLY = i-1;
					elseif strcmp(data{i},'RX')
						idxRX = i-1;
					elseif strcmp(data{i},'RY')
						idxRY = i-1;
					elseif strcmp(data{i},'LP')
						idxLP = i-1;
					elseif strcmp(data{i},'RP')
						idxRP = i-1;
					elseif strcmp(data{i},'X')
						idxX = i-1;
					elseif strcmp(data{i},'Y')
						idxY = i-1;
					elseif strcmp(data{i},'P')
						idxP = i-1;
					elseif strcmp(data{i},'C')
						idxC = i-1;
					end
				end
				
				i = size(PARAM,1);
				j = size(data,2);
				PARAM{i+1,1} = data{1};
				if j==2
					PARAM{i+1,2} = data{2};
				elseif j>2
					PARAM{i+1,2} = data(2:end);
				end
			elseif strcmp(data{1}, '#RECORDED_EYE')
				recordedEye = data{2};
				
				i = size(PARAM,1);
				j = size(data,2);
				PARAM{i+1,1} = data{1};
				if j==2
					PARAM{i+1,2} = data{2};
				elseif j>2
					PARAM{i+1,2} = data(2:end);
				end
			elseif strcmp(data{1}, '#CALPOINT')
			
			elseif strcmp(data{1}, '#XPARAM')
			
			elseif strcmp(data{1}, '#YPARAM')
			
			else % other options
				i = size(PARAM,1);
				j = size(data,2);
				PARAM{i+1,1} = data{1};
				if j==1
					PARAM{i+1,2} = [];
				elseif j==2
					PARAM{i+1,2} = data{2};
				elseif j>2
					PARAM{i+1,2} = data(2:end);
				end
			end
			
		else % gaze data
			T = [T; str2num(data{idxT})];
			if recordedEye == 'B'
				xL = str2num(data{idxLX});
				yL = str2num(data{idxLY});
				xR = str2num(data{idxRX});
				yR = str2num(data{idxRY});
				LHV = [LHV; xL, yL];
				RHV = [RHV; xR, yR];
				if ~(idxLP==-1 && idxRP==-1)
					lP = str2num(data{idxLP});
					rP = str2num(data{idxRP});
					LP = [LP; lP];
					RP = [RP; rP];
				end
			else
				x = str2num(data{idxX});
				y = str2num(data{idxY});
				if isempty(x)
					x = NaN;
				end
				if isempty(y)
					y = NaN;
				end
				HV = [HV; x, y];
				if idxP~=-1
					p = str2num(data{idxP});
					if isempty(p)
						p = NaN;
					end
					P = [P; p];
				end
			end
			if idxC~=-1
				C = [C; data{idxC}];
			end
		end
		
		
		l = fgetl(fp);
	end
	
	fclose(fp);
	
	res = DATA;
	return
	
function res = sgttbx_cnv_split(string, sep)
	idx = findstr(string, sep);
	if isempty(idx)
		res = {string};
		return
	end

	idx = [0,idx,length(string)+1];
	res = cell(1,length(idx)-1);
	for i=1:length(idx)-1
		res{i} = string((idx(i)+1):(idx(i+1)-1));
	end

	return
