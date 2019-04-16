#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include "dsp_functions.h"
#include "functions.h"
#include "klessydra_defs.h"

#define NumOfThreads 3

#ifndef NumOfElements
	#define NumOfElements 10
#endif


#ifndef TIME
	#define TIME 10
#endif

int8_t  vect8_1[NumOfElements];
int16_t vect16_1[NumOfElements];
int32_t vect32_1[NumOfElements];
int8_t  testres8[NumOfElements];
int16_t testres16[NumOfElements];
int32_t testres32[NumOfElements];
int8_t  *res8;
int16_t *res16;
int32_t *res32;
int8_t  result8[NumOfElements];
int16_t result16[NumOfElements];
int32_t result32[NumOfElements];
int testperf[NumOfThreads], perf8[NumOfThreads], perf16[NumOfThreads], perf32[NumOfThreads];
int size8=NumOfElements*sizeof(char);
int size16=NumOfElements*sizeof(short);
int size32=NumOfElements*sizeof(int);


int main()
{
	srand (TIME);
	for (int i=0; i<NumOfElements; i++) 
	{ 
    	vect8_1[i]  = rand()  % (0x100 - 0x1) +1;
    	vect16_1[i] = rand()  % (0x10000 - 0x1) +1;
    	vect32_1[i] = rand()  % (0x80000000 - 0x1) +1;
	}

	
	int dsp_perf8  = 0;
	int dsp_perf16 = 0;
	int dsp_perf32 = 0;
	int test_perf_i = 0;
	int* dsp_ptr_perf8 = &dsp_perf8;
	int* dsp_ptr_perf16 = &dsp_perf16;
	int* dsp_ptr_perf32 = &dsp_perf32;
	int* test_ptr_perf = &test_perf_i;

	int sra_pass;
	/************************************ 8-bit RELU Start ***************************************/

	// ENABLE COUNTING -------------------------------------------------------------------------
	__asm__("csrrw zero, mcycle, zero;"
			"csrrw zero, 0x7A0, 0x00000001");
	//------------------------------------------------------------------------------------------
	
	// TEST KRELU8 ----------------------------------------------------------------------------	
	res8=kless_rectify_linear_unit_8((void*) result8, (void*) vect8_1, size8);
	//------------------------------------------------------------------------------------------

	// DISABLE COUNTING AND SAVE MCYCLE OF EACH THREAD -----------------------------------------
	__asm__("csrrw zero, 0x7A0, 0x00000000;"
			"csrrw %[dsp_perf8], mcycle, zero;"
			"sw %[dsp_perf8], 0(%[dsp_ptr_perf8]);"
			:
			:[dsp_perf8] "r" (dsp_perf8), [dsp_ptr_perf8] "r" (dsp_ptr_perf8)
			);
	if (Klessydra_get_coreID()==0) {perf8[0]=dsp_perf8; } //printf("Speed: %d Cycles\n", perf8[0]);}
	if (Klessydra_get_coreID()==1) {perf8[1]=dsp_perf8; } //printf("Speed: %d Cycles\n", perf8[1]);}
	if (Klessydra_get_coreID()==2) {perf8[2]=dsp_perf8; } //printf("Speed: %d Cycles\n", perf8[2]);}
	//------------------------------------------------------------------------------------------
	
	// Test 8-bit relu result -----------------------------------------------------------------
	sra_pass = 0;
	if (Klessydra_get_coreID()==1)
	{
		__asm__( "csrrw zero, 0x7A0, 0x00000001;");
		for (int i=0; i<NumOfElements; i++)
		{
			if (vect8_1[i] < 0)
			{
				testres8[i] = 0;
			}
			else
			{
				testres8[i] = vect8_1[i];
			}
		}
		__asm__("csrrw zero, 0x7A0, 0x00000000;"
			"csrrw %[test_perf_i], mcycle, zero;"
			"sw %[test_perf_i], 0(%[test_ptr_perf]);"
			:
			:[test_perf_i] "r" (test_perf_i), [test_ptr_perf] "r" (test_ptr_perf)
			);
		testperf[0]=test_perf_i;
		/*
		for (int i=0; i<NumOfElements; i++)
		{
			printf("\ntestres8: %x",testres8[i]);
			printf("\nres8: %x",res8[i]);
		}
		*/
		for (int i=0; i<NumOfElements; i++)
		{
			if (res8[i]==testres8[i])
			{
				sra_pass++;
			}
			else 
			{
				goto FAIL_RELU_8;
			}
		}
		if (sra_pass==NumOfElements)
		{
			printf("\nPASSED KRELU8  8-bit  rectified linear unit");
		}
	}

	// -----------------------------------------------------------------------------------------
	
	/************************************ 8-bit RELU END *****************************************/

	/************************************ 16-bit RELU Start **************************************/
	RELU_16:
	sra_pass = 0;
	
	// ENABLE COUNTING -------------------------------------------------------------------------
	__asm__("csrrw zero, 0x7A0, 0x00000001");
	//------------------------------------------------------------------------------------------

	// TEST KRELU16 ---------------------------------------------------------------------------
	res16=kless_rectify_linear_unit_16((void*) result16, (void*) vect16_1, size16);
	//------------------------------------------------------------------------------------------
	// DISABLE COUNTING AND SAVE MCYCLE OF EACH THREAD ////////
	__asm__("csrrw zero, 0x7A0, 0x00000000;"
	    	"csrrw %[dsp_perf16], mcycle, zero;"
			"sw %[dsp_perf16], 0(%[dsp_ptr_perf16]);"
			:
			:[dsp_perf16] "r" (dsp_perf16), [dsp_ptr_perf16] "r" (dsp_ptr_perf16)
			);
	if (Klessydra_get_coreID()==0) perf16[0]=dsp_perf16;
	if (Klessydra_get_coreID()==1) perf16[1]=dsp_perf16;
	if (Klessydra_get_coreID()==2) perf16[2]=dsp_perf16;
	//------------------------------------------------------------------------------------------
	
	// Test 16-bit relu result ----------------------------------------------------------------
	if (Klessydra_get_coreID()==1)
	{
		__asm__( "csrrw zero, 0x7A0, 0x00000001;");
		for (int i=0; i<NumOfElements; i++)
		{
			if (vect16_1[i] < 0)
			{
				testres16[i] = 0;
			}
			else
			{
				testres16[i] = vect16_1[i];
			}
		}
		__asm__("csrrw zero, 0x7A0, 0x00000000;"
			"csrrw %[test_perf_i], mcycle, zero;"
			"sw %[test_perf_i], 0(%[test_ptr_perf]);"
			:
			:[test_perf_i] "r" (test_perf_i), [test_ptr_perf] "r" (test_ptr_perf)
			);
		testperf[1]=test_perf_i;
		/*
		for (int i=0; i<NumOfElements; i++)
		{
			printf("\ntestres16: %x",testres16[i]);
			printf("\nres16: %x",res16[i]);
		}
		*/
		for (int i=0; i<NumOfElements; i++)
		{
			if (res16[i]==testres16[i])
			{
				sra_pass++;
			}
			else 
			{
				goto FAIL_RELU_16;
			}
		}
		if (sra_pass==NumOfElements)
		{
			printf("\nPASSED KRELU16 16-bit rectified linear unit");
		}
	}
	// --------------------------------------------------------------------------------------------

	/************************************ 16-bit RELU END ****************************************/		

	/************************************ 32-bit SEAV Start **************************************/
	RELU_32:
	sra_pass = 0;
	
	// ENABLE COUNTING ---------------------------------------------------------------------------
	__asm__("csrrw zero, 0x7A0, 0x00000001");
	//--------------------------------------------------------------------------------------------
	
	// TEST KRELU --------------------------------------------------------------------------------	
	res32=kless_rectify_linear_unit_32((void*) result32, (void*) vect32_1, size32);
	//--------------------------------------------------------------------------------------------
	
	// DISABLE COUNTING AND SAVE MCYCLE OF EACH THREAD -------------------------------------------
	__asm__("csrrw zero, 0x7A0, 0x00000000;"
	    	"csrrw %[dsp_perf32], mcycle, zero;"
			"sw %[dsp_perf32], 0(%[dsp_ptr_perf32]);"
			:
			:[dsp_perf32] "r" (dsp_perf32), [dsp_ptr_perf32] "r" (dsp_ptr_perf32)
			);
	if (Klessydra_get_coreID()==0) perf32[0]=dsp_perf32;
	if (Klessydra_get_coreID()==1) perf32[1]=dsp_perf32;
	if (Klessydra_get_coreID()==2) perf32[2]=dsp_perf32;
	//--------------------------------------------------------------------------------------------
	
	// Test 32-bit RELU result -------------------------------------------------------------------
	sra_pass = 0;
	if (Klessydra_get_coreID()==1)
	{
		__asm__( "csrrw zero, 0x7A0, 0x00000001;");
		for (int i=0; i<NumOfElements; i++)
		{
			if (vect32_1[i] < 0)
			{
				testres32[i] = 0;
			}
			else
			{
				testres32[i] = vect32_1[i];
			}
		}
		__asm__("csrrw zero, 0x7A0, 0x00000000;"
			"csrrw %[test_perf_i], mcycle, zero;"
			"sw %[test_perf_i], 0(%[test_ptr_perf]);"
			:
			:[test_perf_i] "r" (test_perf_i), [test_ptr_perf] "r" (test_ptr_perf)
			);
		testperf[2]=test_perf_i;
		/*
		for (int i=0; i<NumOfElements; i++)
		{
			printf("\ntestres32: %x",testres32[i]);
			printf("\nres32: %x",res32[i]);
		}
		*/
		for (int i=0; i<NumOfElements; i++)
		{
			if (res32[i]==testres32[i])
			{
				sra_pass++;
			}
			else 
			{
				goto FAIL_RELU_32;
			}
		}
		if (sra_pass==NumOfElements)
		{
			printf("\nPASSED KRELU32 32-bit rectified linear unit\n\n");
		}
	}
	// -------------------------------------------------------------------------------------------
	
	/************************************ 32-bit RELU END ***************************************/
	
	if (Klessydra_get_coreID()==1)
	{		
		printf("\nNumber of Elements: %d\n",NumOfElements);
		for(int i=0;i<3;i++)
		{
				printf("Th%d KRELU8  Speed: %d Cycles\n",i, perf8[i]);
		}
		for(int i=0;i<3;i++)
		{
				printf("Th%d KRELU16 Speed: %d Cycles\n",i, perf16[i]);
		}
		for(int i=0;i<3;i++)
		{
				printf("Th%d KRELU32 Speed: %d Cycles\n",i, perf32[i]);
		}
		for(int i=0;i<3;i++)
		{
				printf("RELU%d Speed: %d Cycles\n",8*(2^i), testperf[i]);
		}
		return 0;
	}	

	__asm__("csrrw zero, mstatus, 8;" "wfi;");
	return 0;

	FAIL_RELU_8: 
	printf("\nFAILED KRELU8  8-bit rectified linear unit");
	goto RELU_16;
	FAIL_RELU_16: 
	printf("\nFAILED KRELU16 16-bit rectified linear unit");
	goto RELU_32;
	FAIL_RELU_32: 
	printf("\nFAILED KRELU32 32-bit rectified linear unit\n");
	if (Klessydra_get_coreID()==1)
	{		
		printf("\nNumber of Elements: %d\n\n",NumOfElements);
	}
 	return 1;
}

