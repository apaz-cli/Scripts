#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>
#include <cuda_runtime.h>
#include <vector>
#include <string.h>
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

void* launch_gpu_torture(void* arg) {
  (void)arg;
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
            fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
            return;
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
    if (cudaMalloc(&d_data_blocks, n_blocks * sizeof(float*)) != cudaSuccess) {
        fprintf(stderr, "Failed to allocate device memory for data blocks\n");
        return;
    }
    if (cudaMemcpy(d_data_blocks, gpu_memory_blocks.data(), n_blocks * sizeof(float*), cudaMemcpyHostToDevice) != cudaSuccess) {
        fprintf(stderr, "Failed to copy data blocks to device\n");
        return;
    }
    
    dim3 block(BLOCK_SIZE);
    dim3 grid((total_elements + BLOCK_SIZE - 1) / BLOCK_SIZE);

    gpu_torture_kernel<<<grid, block>>>(d_data_blocks, n_blocks, block_size);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
    } else {
        err = cudaDeviceSynchronize();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
        } else {
            puts("GPU torture kernel finished");
        }
    }

    // Free allocated memory
    for (auto block : gpu_memory_blocks) {
        cudaFree(block);
    }
    cudaFree(d_data_blocks);
}

/*******/
/* CPU */
/*******/

void *infinite_loop(void *unused) {
  while (1)
    ;
}

char *store_mem = NULL;

void alloc_mem(size_t n_bytes) {
  if (n_bytes == 0)
    return;

  size_t n_b = n_bytes;
  store_mem = (char *)calloc(1, n_b);
  if (!store_mem)
    puts("malloc() failed."), exit(1);

  for (size_t i = 0; i < n_b; i++)
    store_mem[i] = 0;
}


void torture_cpu(void) {
    // Create one minus the number of CPUs threads. The last one is this thread.
    int numThreads = sysconf(_SC_NPROCESSORS_ONLN) - 1; 
    pthread_t threads[numThreads];
    int rc;
    for (size_t t = 0; t < numThreads; t++) {
        rc = pthread_create(&threads[t], NULL, infinite_loop, NULL);
        if (rc) {
            printf("ERROR; return code from pthread_create() is %d\n", rc);
            exit(1);
        }
    }

    infinite_loop(NULL);
}

int main(int argc, char **argv) {
    size_t mem_bytes = 0;
    bool run_cpu = false;
    bool run_gpu = false;

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--cpu") == 0) {
            run_cpu = true;
        } else if (strcmp(argv[i], "--gpu") == 0) {
            run_gpu = true;
        } else if (strncmp(argv[i], "--mem=", 6) == 0) {
            char* mem_str = argv[i] + 6;
            char* endptr;
            double mem_value = strtod(mem_str, &endptr);
            if (mem_value <= 0 || mem_str == endptr) {
                fprintf(stderr, "Invalid memory value: %s\n", mem_str);
                return 1;
            }
            if (*endptr == '\0' || strcasecmp(endptr, "B") == 0) {
                mem_bytes = (size_t)mem_value;
            } else if (strcasecmp(endptr, "K") == 0 || strcasecmp(endptr, "KB") == 0) {
                mem_bytes = (size_t)(mem_value * 1024);
            } else if (strcasecmp(endptr, "M") == 0 || strcasecmp(endptr, "MB") == 0) {
                mem_bytes = (size_t)(mem_value * 1024 * 1024);
            } else if (strcasecmp(endptr, "G") == 0 || strcasecmp(endptr, "GB") == 0) {
                mem_bytes = (size_t)(mem_value * 1024 * 1024 * 1024);
            } else {
                fprintf(stderr, "Invalid memory unit: %s\n", endptr);
                return 1;
            }
        } else {
            fprintf(stderr, "Usage: %s [--cpu] [--gpu] [--mem=<size>[B|K|M|G]]\n", argv[0]);
            return 1;
        }
    }

    if (!run_cpu && !run_gpu) {
        fprintf(stderr, "Error: At least one of --cpu or --gpu must be specified.\n");
        return 1;
    }

    alloc_mem(mem_bytes);

    pthread_t gpu_thread;
    if (run_gpu) {
        // Initialize CUDA
        int deviceCount;
        cudaError_t err = cudaGetDeviceCount(&deviceCount);
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
            return 1;
        }
        if (deviceCount == 0) {
            fprintf(stderr, "No CUDA devices found\n");
            return 1;
        }
        err = cudaSetDevice(0);
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error: %s\n", cudaGetErrorString(err));
            return 1;
        }

        // Create GPU torture thread
        if (pthread_create(&gpu_thread, NULL, launch_gpu_torture, NULL) != 0) {
            fprintf(stderr, "Failed to create GPU torture thread\n");
            return 1;
        }
    }

    if (run_cpu) {
        torture_cpu();
    }

    return 0;
}
