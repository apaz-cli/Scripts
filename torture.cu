#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>
#include <cuda_runtime.h>

#define CUDA_CHECK(call) \
    do { \
        cudaError_t error = call; \
        if (error != cudaSuccess) { \
            fprintf(stderr, "CUDA error at %s:%d - %s\n", __FILE__, __LINE__, \
                    cudaGetErrorString(error)); \
            exit(1); \
        } \
    } while(0)

#define BLOCK_SIZE 256
#define NUM_BLOCKS 1024

void *infinite_loop(void *unused) {
  while (1)
    ;
}

char *store_mem = NULL;

void alloc_mem(int n_gb) {
  if (n_gb <= 0)
    return;

  size_t n_b = (size_t)n_gb * 1000 * 1000 * 1000;
  store_mem = (char *)calloc(1, n_b);
  if (!store_mem)
    puts("malloc() failed."), exit(1);

  for (size_t i = 0; i < n_b; i++)
    store_mem[i] = 0;
}

__global__ void gpu_torture_kernel(float *data, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        float x = 1.0f;
        for (int i = 0; i < 1000000; i++) {
            x = sinf(x) * cosf(x) * sqrtf(x);
        }
        data[idx] = x;
    }
}

void launch_gpu_torture() {
    int n = BLOCK_SIZE * NUM_BLOCKS;
    float *d_data;
    CUDA_CHECK(cudaMalloc(&d_data, n * sizeof(float)));

    dim3 block(BLOCK_SIZE);
    dim3 grid(NUM_BLOCKS);

    while (1) {
        gpu_torture_kernel<<<grid, block>>>(d_data, n);
        CUDA_CHECK(cudaDeviceSynchronize());
    }

    // This will never be reached, but good practice
    CUDA_CHECK(cudaFree(d_data));
}

void load_threads(void) {
    int numThreads = sysconf(_SC_NPROCESSORS_ONLN) - 1; // Get the number of processors.
    pthread_t threads[numThreads];
    int rc;
    for (size_t t = 0; t < numThreads; t++) {
        rc = pthread_create(&threads[t], NULL, infinite_loop, NULL);
        if (rc) {
            printf("ERROR; return code from pthread_create() is %d\n", rc);
            exit(1);
        }
    }

    // Launch GPU torture in the main thread
    launch_gpu_torture();
}

int main(int argc, char **argv) {
    int n_gb = -1;
    if (argc < 2)
        n_gb = 0;
    else if (argc == 2)
        n_gb = atoi(argv[1]);
    else
        return puts("Usage: load_all_threads <n_gb>"), 1;

    // Initialize CUDA
    int deviceCount;
    CUDA_CHECK(cudaGetDeviceCount(&deviceCount));
    if (deviceCount == 0) {
        fprintf(stderr, "No CUDA devices found\n");
        exit(1);
    }
    CUDA_CHECK(cudaSetDevice(0));

    alloc_mem(n_gb);
    load_threads();
    return 0;
}
