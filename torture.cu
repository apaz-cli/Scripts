#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>
#include <cuda_runtime.h>
#include <vector>

/*******/
/* GPU */
/*******/

#define BLOCK_SIZE 256
#define HALF_GB (size_t)(512 * 1024 * 1024)

#define CUDA_CHECK(call) \
    do { \
        cudaError_t _cu_error = call; \
        if (_cu_error != cudaSuccess) { \
            fprintf(stderr, "CUDA error at %s:%d - %s\n", __FILE__, __LINE__, \
                    cudaGetErrorString(_cu_error)); \
            return _cu_error; \
        } \
    } while(0)

__global__ void gpu_torture_kernel(float **data_blocks, size_t n_blocks, size_t block_size) {
    size_t thread_id = blockIdx.x * blockDim.x + threadIdx.x;
    size_t total_elements = n_blocks * block_size;
    
    if (thread_id < total_elements) {
        size_t block_idx = thread_id / block_size;
        size_t element_idx = thread_id % block_size;
        
        float x = 1.0f;
        float y = 2.0f;
        float z = 3.0f;
        
        for (int i = 0; i < 1000000; i++) {
            x = sinf(x) * cosf(y) * tanf(z);
            y = expf(x) * logf(fabsf(y)) * sqrtf(fabsf(z));
            z = powf(x, y) * fmodf(z, 3.14159f);
            
            // Access and modify data from different blocks
            for (size_t j = 0; j < n_blocks; j++) {
                size_t idx = (block_idx + j) % n_blocks;
                float* block = data_blocks[idx];
                float val = block[(element_idx + j) % block_size];
                x += val;
                y *= val;
                z -= val;
            }
        }
        
        // Write results back to all blocks
        for (size_t j = 0; j < n_blocks; j++) {
            size_t idx = (block_idx + j) % n_blocks;
            float* block = data_blocks[idx];
            block[(element_idx + j) % block_size] = x + y + z;
        }
    }
}

cudaError_t launch_gpu_torture() {
    std::vector<float*> gpu_memory_blocks;
    size_t total_allocated = 0;
    
    while (true) {
        float* d_data;
        cudaError_t err = cudaMalloc(&d_data, HALF_GB);
        if (err != cudaSuccess) {
            if (err == cudaErrorMemoryAllocation) {
                cudaGetLastError(); // Clear the error
                break;  // We've used all available memory
            }
            return err;
        }
        
        gpu_memory_blocks.push_back(d_data);
        total_allocated += HALF_GB;
    }
    
    printf("Total GPU memory allocated: %.2f GB\n", total_allocated / (1024.0 * 1024.0 * 1024.0));
    
    size_t n_blocks = gpu_memory_blocks.size();
    size_t block_size = HALF_GB / sizeof(float);
    size_t total_elements = n_blocks * block_size;
    
    // Allocate and copy device pointers to GPU
    float **d_data_blocks;
    CUDA_CHECK(cudaMalloc(&d_data_blocks, n_blocks * sizeof(float*)));
    CUDA_CHECK(cudaMemcpy(d_data_blocks, gpu_memory_blocks.data(), n_blocks * sizeof(float*), cudaMemcpyHostToDevice));
    
    dim3 block(BLOCK_SIZE);
    dim3 grid((total_elements + BLOCK_SIZE - 1) / BLOCK_SIZE);
    
    while (1) {
        gpu_torture_kernel<<<grid, block>>>(d_data_blocks, n_blocks, block_size);
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaDeviceSynchronize());
        puts("GPU torture kernel finished");
    }
    
    return cudaSuccess;
}

/*******/
/* CPU */
/*******/

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


void torture_cpu(void) {
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
    
    cudaError_t result = launch_gpu_torture();
    if (result != cudaSuccess) {
        fprintf(stderr, "GPU torture failed: %s\n", cudaGetErrorString(result));
        return 1;
    }
    
    torture_cpu();
    return 0;
}
