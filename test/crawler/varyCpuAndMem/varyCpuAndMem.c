//#define _LARGEFILE64_SOURCE
//#define _FILE_OFFSET_BITS 64
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <fcntl.h>
/* for time tracking */
#include <time.h>
#include <sys/time.h>
#include <math.h>

#define MAX(a,b) ((a < b) ? b : a)
#define MIN(a,b) ((a < b) ? a : b)

typedef enum { FALSE, TRUE } bool;

double START_TIME = 0.0;
/* CONFIGS (TODO: CAN MAKE ALL CMDLINE OPTS) */
int RUNTIME_SEC = 1; //Total workload runtime
int WKLD_PERIOD_SEC = 240; // PERIOD OF A ONE FULL SINUSOIDAL WKLD CYCLE
int UPDATE_FREQ_SEC = 20; // HOW OFTEN WE UPDATE THE MEM and CPU ALLOCS
int MAX_MEM_MB = 900;
int MIN_MEM_MB = 100;
int MAX_CPU_PERC = 100;
int MIN_CPU_PERC = 10;

/*****************************************************************************
 * Parses the argv 
 * Identifies VM count and files
 *****************************************************************************/
int parse_argv(int _argc_, char **_argv_)
{
  if ( ((_argc_ == 1) || (strcmp(_argv_[1], "-h")==0)) )
  {
    fprintf(stderr, "Workload Generator:");
    fprintf(stderr, "  Creates a sinusoidal CPU and MEM workload pattern.");
    fprintf(stderr, "Configurables:");
    fprintf(stderr, "  Total workload duration [cmdline].");
    fprintf(stderr, "  CPU and MEM max/min ranges [hardcoded - TODO cmdline].");
    fprintf(stderr, "  Update granularity (update interval for the allocations based on the sin() fit [hardcoded - TODO cmdline].");
    fprintf(stderr, "Usage: %s -t <Runtime [s]> \n\n", _argv_[0]);
    fprintf(stderr, "   Ex: %s -t 60 --> runs for 60s \n", _argv_[0]);
    fprintf(stderr, "  \n");
    exit(1);
  }

  if (strcmp(_argv_[1], "-t") == 0)
  {
     RUNTIME_SEC = atoi(_argv_[2]);
     fprintf(stdout, "Will run for %ds\n", RUNTIME_SEC);
  }
  else
  {
    fprintf(stderr,"\n\n\tDON't UNDERSTAND OPTION %s %s..\n", _argv_[1], _argv_[2]);
    fprintf(stderr,"\n\n\tShould be: -t <Runtime [s]> \n");
    exit(2);
  }

  return 0;
}

/*****************************************************************************
 * This returns the current wall clock time in secs
 *****************************************************************************/
double GetCurrentTimeInSecs(void)
{
  struct timeval t1;
    
  gettimeofday (&t1, NULL); /* will return time since Jan 1st 1970 */
  
  return ( (double) t1.tv_sec + ((double) t1.tv_usec)/1000000.0);
}

/*****************************************************************************
 * This returns the elapsed wall clock time in secs since we started actual execution
 *****************************************************************************/
double ElapsedTimeInSecs(void)
{
  return (GetCurrentTimeInSecs() - START_TIME);
}

/*****************************************************************************
 * This allocs desired size of memory before actual bench kernel 
 * returns: the ptr to alloced memory in "ptr" 
 *          numpages as return                                   
 *****************************************************************************/ 
int SetupMemory( /*ip*/ int sizeMB, int pageSize, /*op*/ char ** ptr)
{
   int sizeB;
   int numPages;

   sizeB = sizeMB * 1024 * 1024;
   (*ptr) = malloc(sizeB);
   if (!(*ptr)) {
     printf("could not allocate %d bytes\n", sizeB);
     exit(1);
   }
   numPages = sizeB / pageSize;

   return numPages;
}

/*****************************************************************************
 * This runs the actual kernel 
 *****************************************************************************/ 
int MemoryLoop(/*ip*/ const char * ptr, int pageSize, int numPages)
{
   int j=0, k=0;
   char *temp;
   int counter = 0;
   int offsetWithinPage = 0;

   for (k=0; k<10; k++)
   {
	  temp = (char *) ptr;
	  for (j=0; j<numPages; j++) 
	  {
		 /* Touch one byte on each page */
		 offsetWithinPage = (rand() % pageSize);
		 *(temp+offsetWithinPage) = (char)(rand());
		 counter += (char)(*(temp+offsetWithinPage));
		 temp = temp + pageSize;
	  }
   }
   return counter;
}



/*****************************************************************************
 * MAIN
 *****************************************************************************/ 
int main(int argc, char** argv)
{
  START_TIME = GetCurrentTimeInSecs();
  double lastCheckPointTimeSec = 0.0;
  double currentIterTimeSec = 0.0;
  bool newMemAllocation = TRUE;  
  bool newCpuAllocation = TRUE;  
  int sizeMB=-1; int sizeNewMB=MIN_MEM_MB; 
  int cpuNewPerc = MIN_CPU_PERC;
  char * ptr = NULL;
  int pageSize = 4096 /* default 4K but check anyways*/; 
  int numPages = 1;
  double microkernelTimeSec = 1.0;
  double usleepRatio = 1.0;
  double usleeptime = 0.01 * 1000000.0;
  int counter = 0;
  
  parse_argv(argc, argv);
  
  lastCheckPointTimeSec = ElapsedTimeInSecs();
  while (ElapsedTimeInSecs() < RUNTIME_SEC) {
    double elapsedTime = ElapsedTimeInSecs();

    currentIterTimeSec = elapsedTime - lastCheckPointTimeSec;
    /* If it is time to recompute Mem/CPU allocs, do based on sinus scaling */
    if (currentIterTimeSec >= UPDATE_FREQ_SEC) {
      int periodDelta = ((int)elapsedTime % WKLD_PERIOD_SEC);
      double periodRatio = (double) periodDelta / (double) WKLD_PERIOD_SEC;
      double scalingFactor = 0.5*( sin(periodRatio * 2*M_PI) + 1.0);

      fprintf(stdout, "Elapsed time: %.1lfs \n", elapsedTime);
      sizeNewMB = MIN( MIN_MEM_MB + (MAX_MEM_MB - MIN_MEM_MB)*scalingFactor, MAX_MEM_MB );
      cpuNewPerc = MIN( MIN_CPU_PERC + (MAX_CPU_PERC - MIN_CPU_PERC)*scalingFactor, MAX_CPU_PERC );
      fprintf(stdout, "  Updating Allocs: (SF: sin(%.2lf*2PI)=%.2lf) CPU: %d%%, MEM: %dMB\n", 
        periodRatio, scalingFactor, cpuNewPerc, sizeNewMB);
      newMemAllocation = TRUE;
      newCpuAllocation = TRUE;
      lastCheckPointTimeSec = elapsedTime;
    }
    
    if (newMemAllocation) {
      newMemAllocation = FALSE;
      if (sizeNewMB == sizeMB) {
	fprintf(stdout, "  MEM Alloc [%3dMB]: Same as before no real allocation\n", sizeNewMB);
      }
      else {
        double allocTimeSec;
	if (ptr) { 
          free(ptr); 
	}
	numPages = SetupMemory(sizeNewMB, pageSize, &ptr);  
	sizeMB = sizeNewMB;
	// Special handling of first iter after new alloc for bringing in pages
	counter = MemoryLoop(ptr, pageSize, numPages); // run the loop to actually alloc pages
	allocTimeSec = ElapsedTimeInSecs() - elapsedTime;
	fprintf(stdout, "  MEM Alloc [%3dMB]: PgSz: %dB, #Pages: %d, Alloc Time: %.2lfs\n", sizeNewMB, pageSize, numPages, allocTimeSec);
	continue; //skip the below microkernel exec after mem alloc
      }
    }
    
    /* microkernel: */
    counter = MemoryLoop(ptr, pageSize, numPages); 
    /* CPU sleep compute */
    microkernelTimeSec = ElapsedTimeInSecs() - elapsedTime;
    //fprintf(stdout,"%d\n", counter);
    usleepRatio = ( (double)(100 - cpuNewPerc)/(double)(cpuNewPerc) );
    usleeptime = microkernelTimeSec * usleepRatio * 1000000.0; 
    if (newCpuAllocation) {
      newCpuAllocation = FALSE;
      fprintf(stdout, "  CPU Alloc [%4d%%]: Iter Time: %.3lfs, Sleep Time: %.3lfs\n", cpuNewPerc, microkernelTimeSec, usleeptime/1000000.0);
    }
    if (usleeptime > 0.0)
    {
      usleep(usleeptime);
    }
  }

  return counter;
	
}
