#include <iostream>
#include <iomanip>
#include <math.h>
#include <helper_cuda.h>
#include <thrust/complex.h>
#include <algorithm>
//#include <thrust>
using namespace thrust;


#include "ragridder_plan.h"
#include "conv_invoker.h"
#include "cuft.h"
#include "deconv.h"
#include "cugridder.h"
#include "precomp.h"
#include "utils.h"


int main(int argc, char *argv[])
{
	/* Input: M, N1, N2, epsilon method
		method - conv method
		M - number of randomly distributed points
		N1, N2 - output size
		epsilon - tolerance
	*/
	int ier = 0;
	if (argc < 4)
	{
		fprintf(stderr,
				"Usage: W Stacking\n"
				"Arguments:\n"
				"  N1, N2 : image size.\n"
				"  M: The number of randomly distributed points.\n"
				"  epsilon: NUFFT tolerance (default 1e-6).\n"
				"  kerevalmeth: Kernel evaluation method; one of\n"
				"     0: Exponential of square root (default), or\n"
				"     1: Horner evaluation.\n"
				"  method: One of\n"
				"    0: nupts driven (default),\n"
				"    2: sub-problem, or\n");
		return 1;
	}
	int N1, N2;
	PCS sigma = 2.0; // upsampling factor
	int M;

	double inp;
	sscanf(argv[1], "%d", &N1);
	sscanf(argv[2], "%d", &N2);
	sscanf(argv[3], "%d", &M);
	PCS epsilon = 1e-6;
	if(argc>4){
		sscanf(argv[4], "%lf", &inp);
		epsilon = inp;
	}
	int kerevalmeth = 0;
	if(argc>5)sscanf(argv[5], "%d", &kerevalmeth);
	int method=0;
	if(argc>6)sscanf(argv[6], "%d", &method);

	//gpu_method == 0, nupts driven

	//int ier;
	PCS *u;
	CPX *c;
	u = (PCS *)malloc(M * N1 * N2 * sizeof(PCS)); //Allocates page-locked memory on the host.
	c = (CPX *)malloc(M * N1 * N2 * sizeof(CPX));
	PCS *d_u;
	CUCPX *d_c, *d_fk;
	CUCPX *d_fw;
	checkCudaErrors(cudaMalloc(&d_u, M * N1 * N2 * sizeof(PCS)));
	checkCudaErrors(cudaMalloc(&d_c, M * N1 * N2 * sizeof(CUCPX)));
    /// pixel size 
	// generating data
	for (int i = 0; i < M; i++)
	{
		u[i] = randm11()*PI; //xxxxx
		c[i].real(randm11()); // M vis per channel, weight?
		c[i].imag(randm11());
		// wgt[i] = 1;
	}

	PCS *k = (PCS*) malloc(sizeof(PCS)*N1*N2);
	PCS pixelsize = 0.01;
	for (int i=0; i<N2; i++){
		for(int j=0; j<N1; j++){
			k[i*N1+j] = sqrt(1-pow(pixelsize*(i-N2/2),2) - pow(pixelsize*(i-N1/2),2))-1;
		}
	}
	// double a[5] = {-PI/2, -PI/3, 0, PI/3, PI/2}; // change to random data
	// for(int i=0; i<M; i++){
	// 	u[i] = a[i/5];
	// 	v[i] = a[i%5];
	// }
#ifdef DEBUG
	printf("origial input data...\n");
	for(int i=0; i<M; i++){
		printf("%.3lf ",u[i]);
	}
	printf("\n");
	for(int i=0; i<M; i++){
		printf("%.3lf ",c[i].real());
	}
	printf("\n");
#endif
	// ignore the tdirty
	// how to convert ms to vis

	//printf("generated data, x[1] %2.2g, y[1] %2.2g , z[1] %2.2g, c[1] %2.2g\n",x[1] , y[1], z[1], c[1].real());

	// Timing begin
	//data transfer
	checkCudaErrors(cudaMemcpy(d_u, u, M * N1 * N2 * sizeof(PCS), cudaMemcpyHostToDevice)); //u
	checkCudaErrors(cudaMemcpy(d_c, c, M * sizeof(CUCPX), cudaMemcpyHostToDevice));

	/* ----------Step2: plan setting------------*/
	curafft_plan *plan;

	plan = new curafft_plan();
    memset(plan, 0, sizeof(curafft_plan));

	int direction = 1; //inverse
	
	// opts and copts setting
    plan->opts.gpu_device_id = 0;
    plan->opts.upsampfac = sigma;
    plan->opts.gpu_sort = 1;
    plan->opts.gpu_binsizex = -1;
    plan->opts.gpu_binsizey = -1;
    plan->opts.gpu_binsizez = -1;
    plan->opts.gpu_kerevalmeth = kerevalmeth;
    plan->opts.gpu_conv_only = 0;
    plan->opts.gpu_gridder_method = method;

    ier = setup_conv_opts(plan->copts, epsilon, sigma, 1, direction, kerevalmeth); //check the arguements

	if(ier!=0)printf("setup_error\n");

    // plan setting
    // cuda stream malloc in setup_plan
    

    int nf1 = get_num_cells(M,plan->copts);

    
    plan->dim = 1;
    setup_plan(nf1, 1, 1, M, d_u, NULL, NULL, d_c, plan);

	plan->ms = M; ///!!!
	plan->mt = 1;
	plan->mu = 1;
    plan->execute_flow = 1;
	int iflag = direction;
    int fftsign = (iflag>=0) ? 1 : -1;

	plan->iflag = fftsign; //may be useless| conflict with direction
	plan->batchsize = 1;

    plan->copts.direction = direction; // 1 inverse, 0 forward
    PCS *d_fwkerhalf;
    checkCudaErrors(cudaMalloc((void**)&d_fwkerhalf,sizeof(PCS)*(N1/2+1)*(N2/2+1)));
    checkCudaErrors(cudaMalloc((void**)&d_fwkerhalf,sizeof(PCS)*(N1/2+1)*(N2/2+1)));
    PCS *d_k;
    checkCudaErrors(cudaMalloc((void**)&d_k,sizeof(PCS)*(N1/2+1)*(N2/2+1)));
    checkCudaErrors(cudaMemcpy(d_k,k,sizeof(PCS)*(N1/2+1)*(N2/2+1),cudaMemcpyHostToDevice));
    fourier_series_appro_invoker(d_fwkerhalf,d_k,plan->copts,(N1/2+1)*(N2/2+1)); // correction with k, may be wrong, k will be free in this function

	// do conv and then record on the  2D array ++++++++++++++++++

#ifdef DEBUG
	printf("nf1 %d\n",plan->nf1);
	printf("copts info printing...\n");
	printf("kw: %d, direction: %d, pirange: %d, upsampfac: %lf, \nbeta: %lf, halfwidth: %lf, c: %lf\n",
 	plan->copts.kw,
 	plan->copts.direction,
 	plan->copts.pirange,
 	plan->copts.upsampfac,
    plan->copts.ES_beta,
    plan->copts.ES_halfwidth,
    plan->copts.ES_c);

	PCS *fwkerhalf1 = (PCS*)malloc(sizeof(PCS)*((N1/2+1)*(N2/2+1)));
	

	checkCudaErrors(cudaMemcpy(fwkerhalf1,d_fwkerhalf,(N1/2+1)*(N2/2+1)*
	 	sizeof(PCS),cudaMemcpyDeviceToHost));
	
	
	printf("correction factor print...\n");
    for(int j=0; j<N2/2+1; j++){
        for(int i=0; i<N1/2+1; i++){
            printf("%.3g ", fwkerhalf1[i+j*(N1/2+1)]);
        }
	    printf("\n");
    }
	
	// free host fwkerhalf
    free(fwkerhalf1);

#endif

    
	// fw (conv res set)
	checkCudaErrors(cudaMalloc((void**)&d_fw,sizeof(CUCPX)*nf1*N1*N2));
	checkCudaErrors(cudaMemset(d_fw, 0, sizeof(CUCPX)*nf1*N1*N2));
	plan->fw = d_fw;
	// fk malloc and set
	checkCudaErrors(cudaMalloc((void**)&d_fk,sizeof(CUCPX)*N1*N2));
	plan->fk = d_fk;

	// calulating result
	curafft_conv(plan);
#ifdef DEBUG
	printf("conv result printing...\n");
	CPX *fw = (CPX *)malloc(sizeof(CPX)*nf1*nf2);
	PCS temp_res=0;
	cudaMemcpy(fw,plan->fw,sizeof(CUCPX)*nf1*nf2,cudaMemcpyDeviceToHost);
	for(int i=0; i<nf2; i++){
		for(int j=0; j<nf1; j++){
			printf("%.3g ",fw[i*nf1+j].real());
			temp_res += fw[i*nf1+j].real();
		}
		printf("\n");
	}
	printf("fft(0,0) %.3g\n",temp_res);
#endif
	// fft
	CUFFT_EXEC(plan->fftplan, plan->fw, plan->fw, direction);
#ifdef DEBUG 
	printf("fft result printing...\n");
	cudaMemcpy(fw,plan->fw,sizeof(CUCPX)*nf1*nf2,cudaMemcpyDeviceToHost);
	for(int i=0; i<nf2; i++){
		for(int j=0; j<nf1; j++){
			printf("%.3g ",fw[i*nf1+j].real());
		}
		printf("\n");
	}
	free(fw);
#endif
	// printf("correction factor printing...\n");
	// for(int i=0; i<N1/2; i++){
	// 	printf("%.3g ",fwkerhalf1[i]);
	// }
	// printf("\n");
	// for(int i=0; i<N2/2; i++){
	// 	printf("%.3g ",fwkerhalf2[i]);
	// }
	// printf("\n");
	// deconv
	ier = curafft_deconv(plan);

	CPX *fk = (CPX *)malloc(sizeof(CPX)*N1*N2);
	checkCudaErrors(cudaMemcpy(fk,plan->fk,sizeof(CUCPX)*N1*N2, cudaMemcpyDeviceToHost));
	
	// result printing
	printf("final result printing...\n");
	for(int i=0; i<N2; i++){
		for(int j=0; j<N1; j++){
			printf("%.10lf ",fk[i*N1+j].real());
		}
		printf("\n");
	}

	//free
	curafft_free(plan);
	free(fk);
	free(u);
	free(c);

	return ier;
}