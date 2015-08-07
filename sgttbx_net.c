/**********************************************************
% Mex file for SimpeGazeTracker toolbox 0.4.0
% (compatible with SimpleGazeTracker 0.8.2)
% Copyright (C) 2012-2015 Hiroyuki Sogo.
% Distributed under the terms of the GNU General Public License (GPL).
% 
% Part of this program is based on pnet.c Version2.0.5 + PTBMods
% by Mario Kleiner.
%
% Build on Ubuntu/Octave (octaveX.X-header package is necessary)
%   mex sgttbx_net.c
%
% Build on Windows/Matlab (LCC)
%   mex -O sgttbx_net.c winmm.lib wsock32.lib
%
**********************************************************/
                                                          
/******* GENERAL DEFINES *********/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

/******* WINDOWS ONLY DEFINES *********/
//#ifdef WIN32
#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__)
#define IFWINDOWS(dothis) dothis
#define IFUNIX(dothis)
#include <winsock2.h>
extern DWORD _stdcall timeGetTime(void);
#define close(s) closesocket(s)
#define nonblockingsocket(s) {unsigned long ctl = 1;ioctlsocket( s, FIONBIO, &ctl );}
#define s_errno WSAGetLastError()
#define EWOULDBLOCK WSAEWOULDBLOCK
#define usleep(a) Sleep((a)/1000)
#define MSG_NOSIGNAL 0
#define DEFAULT_USLEEP	    1000

/******* NON WINDOWS DEFINES *********/
#else
#define IFWINDOWS(dothis)
#define IFUNIX(dothis) dothis

#include <errno.h>
#define s_errno errno
#include <netdb.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <sys/time.h>
#include <netinet/tcp.h>

#define nonblockingsocket(s)  fcntl(s,F_SETFL,O_NONBLOCK)
#define DEFAULT_USLEEP        500
#endif

#ifndef INADDR_NONE
#define INADDR_NONE (-1)
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

/* Include header file for matlab mex file functionality */
#include "mex.h"

#define MAX_CON	16
#define	CON_FREE	-1
#define STATUS_FREE       -1
#define STATUS_NOCONNECT   0	// Disconnected pipe that is note closed
#define STATUS_TCP_SOCKET  1
#define STATUS_IO_OK       5	// Used for IS_... test
#define STATUS_CONNECT     10	// Used for IS_... test
#define STATUS_TCP_CLIENT  11
#define STATUS_TCP_SERVER  12

#define READ_BUFFER_SIZE	65536
#define	WRITE_BUFFER_SIZE	1024

#define double_inf            HUGE_VAL
#define DEFAULT_WRITETIMEOUT  double_inf
#define DEFAULT_READTIMEOUT   double_inf

#define BACKLOG           50	/* How many pending connections queue will hold */

#define IS_STATUS_IO_OK(x) ((x)>=STATUS_IO_OK)
#define IS_STATUS_CONNECTED(x) ((x)>=STATUS_CONNECT)
#define IS_STATUS_UDP_NO_CON(x) ((x)==STATUS_UDP_CLIENT || (x)==STATUS_UDP_SERVER)
#define IS_STATUS_TCP_CONNECTED(x) ((x)==STATUS_TCP_CLIENT || (x)==STATUS_TCP_SERVER)

typedef struct
{
	char *ptr;
	int len;
	int pos;
} ioBuff;

typedef struct
{
	int fid;
	double readtimeout;
	double writetimeout;
	struct sockaddr_in remote_addr;
	ioBuff write;
	ioBuff read;
	int status;
} ConInfo;


bool g_hasInitialized = 0;
int g_NumOutputs;
mxArray **g_pOutputs;
int g_NumInputs;
const mxArray **g_pInputs;

ConInfo g_ConList[MAX_CON];
int g_CurrentCon = 0;

#ifdef WIN32
double myNow()
{
	double sec;
	sec = ((double) timeGetTime()) / 1000.0;
	return (sec);
}
#else
double myNow()
{
	struct timeval tv;
	double sec;
	gettimeofday (&tv, NULL);
	sec = (double) tv.tv_sec + ((double) tv.tv_usec) / (double) 1e6;
	return (sec);
}
#endif

int findOptionString(const char *trgstr)
{
	char str[81];
	int i, index;
	while(index<g_NumInputs){
		if(mxIsChar(g_pInputs[index])){
			mxGetString(g_pInputs[index], str, sizeof(str)-1);
			for(i=0; i<strlen(str); i++){
				str[i] = toupper(str[i]);
			}
			if(strcmp(str,trgstr)==0){
				return 1;
			}
		}
		index++;
	}
	return 0;
}

double getScalarValue(const mxArray* a)
{
	char buff[81];
	buff[0] = 0;
	if(mxIsChar(a)){
		mxGetString (a, buff, 80);
		return atof(buff);
	}
	
	return mxGetScalar(a);
}

void setReturnValue(int index, double value)
{
	g_pOutputs[index] = mxCreateDoubleMatrix (1, 1, mxREAL);
	if(g_pOutputs[index] == NULL)
		mexErrMsgTxt("Matrix creation error! Lack of memory?");
	else
		*mxGetPr(g_pOutputs[index]) = value;
}

void setReturnMatrix(int index, int rows, int cols, double* m)
{
	double *pr;
	g_pOutputs[index] = mxCreateDoubleMatrix (rows, cols, mxREAL);
	if (g_pOutputs[index] == NULL)
		mexErrMsgTxt ("Matrix creation error");
	pr = (double *) mxGetPr(g_pOutputs[index]);
	memcpy (pr, m, rows * cols * sizeof (double));
}

int setCurrentCon(int id){
	if(id>=MAX_CON || id<0){
		mexErrMsgTxt ("Unvalid value of handler!");
		return -1;
	}
	if(g_ConList[id].status == STATUS_FREE)
	{
		mexErrMsgTxt ("No valid handler! already closed?");
		return -1;
	}
	g_CurrentCon = id;
	return id;
}

int searchFreeCon(void){
	int i;
	for(i=0; i<MAX_CON; i++){
		if(g_ConList[i].status == STATUS_FREE)
			return i;
	}
	mexErrMsgTxt("No free connection!");
	return -1;
}

void initCon(int fid, int status)
{
	memset(&g_ConList[g_CurrentCon], 0, sizeof(ConInfo));
	g_ConList[g_CurrentCon].fid = fid;
	g_ConList[g_CurrentCon].status = status;
	g_ConList[g_CurrentCon].readtimeout = DEFAULT_READTIMEOUT;
	g_ConList[g_CurrentCon].writetimeout = DEFAULT_WRITETIMEOUT;
	g_ConList[g_CurrentCon].read.ptr = malloc(READ_BUFFER_SIZE);
	g_ConList[g_CurrentCon].write.ptr = malloc(WRITE_BUFFER_SIZE);
	if(g_ConList[g_CurrentCon].read.ptr==NULL||g_ConList[g_CurrentCon].write.ptr==NULL)
		mexErrMsgTxt("Internal out of memory!");	
}

void closeCon(int index)
{
	if(g_ConList[index].fid>=0){
		close(g_ConList[index].fid);
	}
	else{
		mexWarnMsgTxt("Closing already closed connection!");
	}
	free(g_ConList[index].read.ptr);
	free(g_ConList[index].write.ptr);
	g_ConList[index].fid=-1;
	g_ConList[index].status=STATUS_FREE;
}

int closeAll (void)
{
	int flag = 0;
	int i;
	for (i=0; i<MAX_CON; i++){
		if (g_ConList[i].fid >= 0) {	/* Already closed?? */
			closeCon(i);
			flag = 1;
		}
	}
	return flag;
}

int ipv4_lookup (const char *hostname, int port)
{
	struct in_addr addr;
	addr.s_addr = inet_addr(hostname);
	if (addr.s_addr == INADDR_NONE) {
		struct hostent *he;
		he = gethostbyname(hostname);
		if (he == NULL) {
			mexPrintf ("\nUNKNOWN HOST:%s\n", hostname);
			return -1;		/* Can not lookup hostname */
		}
		addr = *((struct in_addr *) he->h_addr);
  	}
  	g_ConList[g_CurrentCon].remote_addr.sin_family = AF_INET;
	g_ConList[g_CurrentCon].remote_addr.sin_port = htons (port);
	g_ConList[g_CurrentCon].remote_addr.sin_addr = addr;
	memset (&g_ConList[g_CurrentCon].remote_addr.sin_zero, 0, 8);
	return 0;
}


int tcpConnect(const char *hostname, const int port)
{
	int nodelay_flag = 1;
	
	if (ipv4_lookup (hostname, port) == -1)
		return -1;
	g_ConList[g_CurrentCon].fid = socket(AF_INET, SOCK_STREAM, 0);
	if(g_ConList[g_CurrentCon].fid==CON_FREE){
		closeCon(g_CurrentCon);
		return -1;
	}
	setsockopt(g_ConList[g_CurrentCon].fid, IPPROTO_TCP, TCP_NODELAY, (void*) &nodelay_flag, sizeof(int));
	if(connect(g_ConList[g_CurrentCon].fid,
			   (struct sockaddr*)&g_ConList[g_CurrentCon].remote_addr,
			   sizeof(struct sockaddr)) == -1){
		closeCon(g_CurrentCon);
		return -1;
	}
	g_ConList[g_CurrentCon].status = STATUS_TCP_CLIENT;
	g_ConList[g_CurrentCon].readtimeout = DEFAULT_READTIMEOUT;
	g_ConList[g_CurrentCon].writetimeout = DEFAULT_WRITETIMEOUT;
	g_ConList[g_CurrentCon].read.ptr = malloc(READ_BUFFER_SIZE);
	g_ConList[g_CurrentCon].write.ptr = malloc(WRITE_BUFFER_SIZE);
	if(g_ConList[g_CurrentCon].read.ptr==NULL||g_ConList[g_CurrentCon].write.ptr==NULL)
		mexErrMsgTxt("Internal out of memory!");	
	nonblockingsocket(g_ConList[g_CurrentCon].fid);
	return g_CurrentCon;
}

int tcpSocket(int port)
{
	int sockfd;
	struct sockaddr_in my_addr;
	const int on = 1;
	
#ifndef WIN32
#ifndef IPTOS_LOWDELAY
#define IPTOS_LOWDELAY          0x10
#endif
	int tos = IPTOS_LOWDELAY;
#endif
	
	sockfd = socket (AF_INET, SOCK_STREAM, 0);
	if (sockfd == -1)
		return -1;
	my_addr.sin_family = AF_INET;	/* host byte order */
	my_addr.sin_port = htons (port);	/* short, network byte order */
	my_addr.sin_addr.s_addr = INADDR_ANY;	/* auto-fill with my IP */
	memset (&(my_addr.sin_zero), 0, 8);	/* zero the rest of the struct */
	setsockopt (sockfd, SOL_SOCKET, SO_REUSEADDR, (const char *) &on, sizeof (on));
	if (bind (sockfd, (struct sockaddr *) &my_addr, sizeof (struct sockaddr))== -1) {
		close (sockfd);
		return -1;
	}
	listen(sockfd, BACKLOG);
	nonblockingsocket(sockfd);

	/* Try to enable low-latency send/receive operations on socket: */
#ifndef WIN32
	if (-1 == setsockopt (sockfd, IPPROTO_IP, IP_TOS, &tos, sizeof (tos))) {
		mexPrintf("Warning: Could not enable low-latency mode on socket! [%s]\n", strerror (errno));
  }
#endif

	return sockfd;

}

int tcpiplisten (void)
{
	const double timeoutat = myNow () + g_ConList[g_CurrentCon].readtimeout;
	int new_fd;
	const int sock_fd = g_ConList[g_CurrentCon].fid;
	int sin_size = sizeof (struct sockaddr_in);
	g_CurrentCon = searchFreeCon();
	while (1) {
		if ((new_fd=accept (sock_fd, (struct sockaddr *) &g_ConList[g_CurrentCon].remote_addr, &sin_size)) > -1)
			break;
		if (timeoutat <= myNow ())
			return -1;
		usleep (DEFAULT_USLEEP);
	}
	nonblockingsocket(new_fd);	/* Non blocking read! */
	setsockopt(new_fd, SOL_SOCKET, SO_KEEPALIVE, (void *) 1, 0);	/* realy needed? */
	initCon(new_fd,STATUS_TCP_SERVER);
	return g_CurrentCon;
}


int readbuff (void)
{
	int retval = -1;
	int readlen = READ_BUFFER_SIZE;
	
	if (0 == IS_STATUS_IO_OK(g_ConList[g_CurrentCon].status))
		return -1;
	
	if (IS_STATUS_CONNECTED(g_ConList[g_CurrentCon].status))
		retval = recv(g_ConList[g_CurrentCon].fid, &g_ConList[g_CurrentCon].read.ptr[g_ConList[g_CurrentCon].read.pos], readlen, MSG_NOSIGNAL);
	else {
		struct sockaddr_in my_addr;
		int fromlen = sizeof (my_addr);
		// Copy 0.0.0.0 adress and 0 port to remote_addr as init-value.
		memset (&my_addr, 0, sizeof (my_addr));
		g_ConList[g_CurrentCon].remote_addr.sin_addr = my_addr.sin_addr;
		g_ConList[g_CurrentCon].remote_addr.sin_port = my_addr.sin_port;
		retval = recvfrom(g_ConList[g_CurrentCon].fid,
						  &g_ConList[g_CurrentCon].read.ptr[g_ConList[g_CurrentCon].read.pos],
						  readlen, MSG_NOSIGNAL, (struct sockaddr *) &my_addr,
						  &fromlen);
		if (retval > 0) {
			g_ConList[g_CurrentCon].remote_addr.sin_addr = my_addr.sin_addr;
			g_ConList[g_CurrentCon].remote_addr.sin_port = htons ((unsigned short int)
						   ntohs (my_addr.sin_port));
		}
	}
	if (retval == 0) {
		g_ConList[g_CurrentCon].status = STATUS_NOCONNECT;
		return -1;
	}
	if (retval < 0 && s_errno != EWOULDBLOCK) {
		g_ConList[g_CurrentCon].status = STATUS_NOCONNECT;
		perror ("recvfrom() or recv()");
		return -1;
	}
	readlen = retval > 0 ? retval : 0;
	if (readlen < 1000)
		usleep (DEFAULT_USLEEP);
	
	return readlen;
}


int writedata(int len)
{
	const double timeoutat = myNow () + g_ConList[g_CurrentCon].writetimeout;
	const char *ptr = g_ConList[g_CurrentCon].write.ptr;
	const int fid = g_ConList[g_CurrentCon].fid;
	int sentlen = 0;
	int retval = 0;
	int lastsize = 1000000;

	if (g_ConList[g_CurrentCon].status < STATUS_IO_OK)
		return 0;
	while (sentlen < len) {
		if (lastsize < 1000)
			usleep (DEFAULT_USLEEP);
		retval = send(fid, &ptr[sentlen], len-sentlen, MSG_NOSIGNAL);
		lastsize = retval > 0 ? retval : 0;
		sentlen += lastsize;
		
		if (retval < 0 && s_errno != EWOULDBLOCK) {
			g_ConList[g_CurrentCon].status = STATUS_NOCONNECT;
			perror ("sendto() / send()");
			mexPrintf ("\nREMOTE HOST DISCONNECTED\n");
			break;
		}
		if (!IS_STATUS_TCP_CONNECTED (g_ConList[g_CurrentCon].status) && sentlen == len)
			break;
		if (timeoutat <= myNow ())
			break;
	}
	return sentlen;
}

void CleanUpMex (void)
{
	if (closeAll ())		/* close all still open connections... */
		mexWarnMsgTxt("Unloading mex file. Unclosed tcp/udp/ip connections will be closed!");
	IFWINDOWS(WSACleanup(););
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
	char funcstr[81];
	char hostname[128];
	int port, fd;
	int i;
	unsigned char *p;
	mxChar *mxcp;
	/*initialization*/
	if(!g_hasInitialized){
#ifdef WIN32
		WORD wVersionRequested;
		WSADATA wsaData;
		int wsa_err;
		wVersionRequested = MAKEWORD (2, 0);
		wsa_err = WSAStartup (wVersionRequested, &wsaData);
		if (wsa_err)
			mexErrMsgTxt ("Error starting WINSOCK32.");
#endif
		mexAtExit (CleanUpMex);
		g_CurrentCon = 0;
		for (i=0; i < MAX_CON; i++){
			memset(&g_ConList[i], 0, sizeof(ConInfo));
			g_ConList[i].fid = -1;
			g_ConList[i].status = STATUS_FREE;
		}
		g_hasInitialized = 1;
	}
	g_NumOutputs = nlhs;
	g_pOutputs = plhs;
	g_NumInputs = nrhs;
	g_pInputs = prhs;
	
	if(g_NumInputs<=0){
		mexErrMsgTxt("No input.");
	}
	if(mxIsChar(g_pInputs[0])){ /*First argument is fucntion name.*/
		mxGetString(g_pInputs[0], funcstr, sizeof(funcstr)-1);
		for(i=0; i<strlen(funcstr); i++){
			funcstr[i] = toupper(funcstr[i]);
		}
		if(strcmp("CLOSEALL",funcstr)==0){
			closeAll();
			return;
		}else if(strcmp("TCPCONNECT",funcstr)==0){
			if(g_NumInputs<3)
				mexErrMsgTxt("Too few parameters");
			mxGetString(g_pInputs[1], hostname, sizeof(hostname)-1);
			port = (int)getScalarValue(g_pInputs[2]);
			g_CurrentCon = searchFreeCon();
			if(g_CurrentCon>=0)
				setReturnValue(0,tcpConnect(hostname, port));
			else
				setReturnValue(0,-1);
			return;
		}else if(strcmp("TCPSOCKET",funcstr)==0){
			if(g_NumInputs<2)
				mexErrMsgTxt("Too few parameters");
			fd = tcpSocket((int)getScalarValue(g_pInputs[1]));
			if(fd>=0){
				g_CurrentCon = searchFreeCon();
				initCon(fd,STATUS_TCP_SOCKET);
				setReturnValue(0,g_CurrentCon);
			}else{
				setReturnValue(0,-1);
			}
			return;
		}
	}else{ /*First argument is con id.*/
		int id = (int)getScalarValue(g_pInputs[0]);
		if(setCurrentCon(id)<0){
			mexErrMsgTxt ("Unknown connection handler");
			return;
		}
		/*get function name*/
		if(g_NumInputs<2)
				mexErrMsgTxt("No function name");
		mxGetString(g_pInputs[1], funcstr, sizeof(funcstr)-1);
		for(i=0; i<strlen(funcstr); i++){
			funcstr[i] = toupper(funcstr[i]);
		}
			
		if(strcmp("TCPLISTEN",funcstr)==0){
			if(g_ConList[g_CurrentCon].status != STATUS_TCP_SOCKET)
				mexErrMsgTxt("Invalid socket for LISTEN.");
			setReturnValue(0,tcpiplisten());
			return;
		}else if(strcmp("CLOSE",funcstr)==0){
			closeCon(g_CurrentCon);
			return;
		}else if(strcmp("READ",funcstr)==0){
			if (IS_STATUS_TCP_CONNECTED (g_ConList[g_CurrentCon].status)){
				int readlen = readbuff();
				int i;
				mwSize dims[2];
				if(readlen>0){
					dims[0] = 1;
					dims[1] = readlen;
					if(findOptionString("UINT8")==1){
						g_pOutputs[0]=mxCreateNumericArray(2,dims,mxUINT8_CLASS,mxREAL);
						p = (unsigned char *)mxGetData(g_pOutputs[0]);
						for(i=0; i<readlen; i++){
							p[i] = g_ConList[g_CurrentCon].read.ptr[i];
						}
					}else{
						g_pOutputs[0]=mxCreateNumericArray(2,dims,mxCHAR_CLASS,mxREAL);
						mxcp = (mxChar *)mxGetData(g_pOutputs[0]);
						for(i=0; i<readlen; i++){
							mxcp[i] = g_ConList[g_CurrentCon].read.ptr[i];
						}
					return;
					}
				}else{
					dims[0] = 0;
					dims[1] = 0;
					if(findOptionString("UINT8")==1){
						g_pOutputs[0]=mxCreateNumericArray(2,dims,mxUINT8_CLASS,mxREAL);
					}else{
						g_pOutputs[0]=mxCreateNumericArray(2,dims,mxCHAR_CLASS,mxREAL);
					}
					return;
				}
			}
			return;
		}else if(strcmp("WRITE",funcstr)==0){
			if (IS_STATUS_TCP_CONNECTED (g_ConList[g_CurrentCon].status)){
				int len = mxGetNumberOfElements(g_pInputs[2]), i;
				mxChar *ptr = (mxChar *) mxGetData(g_pInputs[2]);
				if(len>WRITE_BUFFER_SIZE)
					mexErrMsgTxt("Write buffer overflow.");
				for(i=0; i<len; i++){
					g_ConList[g_CurrentCon].write.ptr[i] = (char)ptr[i];
				}
				writedata(len);
			}
			return;
		}else if(strcmp("GETHOST",funcstr)==0){
			int i;
			double ip_bytes[4] = { 0, 0, 0, 0 };
			const unsigned char *ipnr =(const unsigned char *) &g_ConList[g_CurrentCon].remote_addr.sin_addr;
			for(i=0; i<4; i++)
				ip_bytes[i] = (double) ipnr[i];
			setReturnMatrix(0, 1, 4, ip_bytes);
			setReturnValue(1,(int)ntohs(g_ConList[g_CurrentCon].remote_addr.sin_port));
			return;
		}else if(strcmp("STATUS",funcstr)==0){
			setReturnValue(0,g_ConList[g_CurrentCon].status);
			return;
		}else if(strcmp("SETREADTIMEOUT",funcstr)==0){
			g_ConList[g_CurrentCon].writetimeout = getScalarValue(g_pInputs[2]);
			return;
		}else if(strcmp("SETWRITETIMEOUT",funcstr)==0){
			g_ConList[g_CurrentCon].writetimeout = getScalarValue(g_pInputs[2]);
			return;
		}
	}
	/*mexErrMsgTxt ("Unknown function");*/
	mexErrMsgTxt (funcstr);
}

