
#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_

#include <mxnet/base.h>

namespace mxnet
{
namespace op
{

#define MASK_WIDTH 5
#define TILE_WIDTH 16
#define KERNEL_SIZE 24*12*MASK_WIDTH*MASK_WIDTH

__constant__ float deviceKernel[KERNEL_SIZE];

__global__ void forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K, const int W_grid)
{

    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.
    We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    */
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    // (void)H_out; // silence declared but never referenced warning. remove this line when you start working
    // (void)W_out; // silence declared but never referenced warning. remove this line when you start working

// An example use of these macros:
// float a = y4d(0,0,0,0)
// y4d(0,0,0,0) = a
#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) deviceKernel[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]
    __shared__ float cache[12][TILE_WIDTH+MASK_WIDTH-1][TILE_WIDTH+MASK_WIDTH-1];

    int n, m, h, w, c, p, q;
    int tx = threadIdx.x;
    int ty = threadIdx.y;
    n = blockIdx.x;
    m = blockIdx.y;
    h = (blockIdx.z / W_grid)*TILE_WIDTH + ty;
    w = (blockIdx.z % W_grid)*TILE_WIDTH + tx;

    for (c = 0; c < C; c++) {
        if (h < H && w < W) {
            cache[c][ty][tx] = x4d(n, c, h, w);
        } else {
            cache[c][ty][tx] = 0;
        }
    }

    __syncthreads();

    float acc = 0;
    if (tx < TILE_WIDTH && ty < TILE_WIDTH && h < H_out && w < W_out) {
        #pragma unroll
        for(c = 0; c < C; c++ ) {
            #pragma unroll
            for(p=0; p < K; p++) {
                #pragma unroll
                for(q = 0; q < K; q++) {
                    if (h+p < H && w+q < W) {
                        acc += cache[c][ty+p][tx+q] * k4d(m, c, p, q);
                    }
                }
            }
        }
        y4d(n, m, h, w) = acc;
    }

#undef y4d
#undef x4d
#undef k4d
}

/* 
   This function is called by new-inl.h
   Any code you write should be executed by this function.
   For ECE408, we only expect the float version of the operator to be called, so here we specialize with only floats.
*/
template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> &y, const mshadow::Tensor<gpu, 4, float> &x, const mshadow::Tensor<gpu, 4, float> &w)
{

    // Use mxnet's CHECK_EQ to do assertions.
    // Remove this assertion when you do your implementation!
    // CHECK_EQ(0, 1) << "Remove this line and replace with your implementation";

    // Extract the tensor dimensions into B,M,C,H,W,K
    // ...

    int B = x.shape_[0];
    int M = y.shape_[1];
    int C = x.shape_[1];
    int H = x.shape_[2];
    int W = x.shape_[3];
    int K = w.shape_[3];

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int W_grid = ceil((float) (W_out - 1)/TILE_WIDTH) + 1; // number of horizontal tiles per output map
    int H_grid = ceil((float) (H_out - 1)/TILE_WIDTH) + 1; // number of vertical tiles per output map

    // int width = (W_out-1) / TILE_WIDTH + 1;
    // int height = (H_out-1) / TILE_WIDTH + 1;

    cudaMemcpyToSymbol(deviceKernel, w.dptr_, M * C * K * K * sizeof(float), 0, cudaMemcpyHostToDevice);

    int Z = H_grid * W_grid;
    dim3 gridDim(B, M, Z);
    dim3 blockDim(TILE_WIDTH+MASK_WIDTH-1, TILE_WIDTH+MASK_WIDTH-1, 1);

    // Call the kernel
    forward_kernel<<<gridDim, blockDim, 0>>>(y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K, W_grid);

    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());

}

/* 
    This tells mxnet how to do an op when it's not a float.
    This is not used in the ECE408 project
*/
template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}

#endif