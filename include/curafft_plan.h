#ifndef __CURAFFT_PLAN_H__
#define __CURAFFT_PLAN_H__


#include <cstdlib>
#include <cufft.h>
#include <assert.h>
#include <cuda_runtime.h>
#include "../src/utils.h"
#include "dataType.h"
#include "curafft_opts.h"
#include "../src/FT/conv_invoker.h"
#include "../src/RA/visibility.h"


struct curafft_plan
{
    curafft_opts opts;
    conv_opts copts;
	//cufft
    cufftHandle fftplan;
	//A stream in CUDA is a sequence of operations that execute on the device in the order in which they are issued 
	//by the host code. While operations within a stream are guaranteed to execute in the prescribed order, operations
	//in different streams can be interleaved and, when possible, they can even run concurrently.
	cudaStream_t *streams;

    //int type;
	
	//suppose the N_u = N_l
	int M; //NU
	int nf1; // UPTS
	int nf2;
	int num_w; //number of w after gridding
	int ms;
	int mt;
	//int mu;
	int ntransf;
	//int maxbatchsize; =1
	

	//int totalnumsubprob;
	int byte_now; //always be set to be 0
	PCS *fwkerhalf1; //used for not just spread only
	PCS *fwkerhalf2;
	//PCS *fwkerhalf3;

	visibility kv;
	int w_term_method; // 0 for w-stacking, 1 for improved w-stacking
	//PCS *kx;
	//PCS *ky;
	//PCS *kz;
	//CUCPX *c;
	//int iflag;


	CUCPX *fw; // output
	CUCPX *fk;

	int *idxnupts;//length: #nupts, index of the nupts in the bin-sorted order (size is M) abs location in bin
	int *sortidx; //length: #nupts, order inside the bin the nupt belongs to (size is M) local position in bin
	INT_M *cell_loc; // length: #nupts, location in grid cells for 2D case


	//----for GM-sort method----
	int *binsize; //length: #bins, number of nonuniform ponits in each bin //one bin can contain add to gpu_binsizex*gpu_binsizey points
	int *binstartpts; //length: #bins, exclusive scan of array binsize // binsize after scan
	
    /*


	// Arrays that used in subprob method
	int *numsubprob; //length: #bins,  number of subproblems in each bin
	
	int *subprob_to_bin;//length: #subproblems, the bin the subproblem works on 
	int *subprobstartpts;//length: #bins, exclusive scan of array numsubprob
    

	// Extra arrays for Paul's method
	int *finegridsize;
	int *fgstartpts;
    
	// Arrays for 3d (need to sort out)
	int *numnupts;
	int *subprob_to_nupts;
    */

};

#endif
