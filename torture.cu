#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <unistd.h>
#include <cuda_runtime.h>
#include <vector>
#include <string.h>
#include <stdint.h>
#include <time.h>
/*******/
/* GPU */
/*******/

#define BLOCK_SIZE 256
#define ONE_GB (size_t)(1024 * 1024 * 1024)
#define HALF_GB (ONE_GB / 2)

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
            fprintf(stderr, "CUDA error allocating memory: %s\n", cudaGetErrorString(err));
            exit(1);
        }
        
        gpu_memory_blocks.push_back(d_data);
        total_allocated += HALF_GB;
    }
    
    printf("Total GPU memory allocated: %.2f GB\n", total_allocated / ONE_GB);
    
    size_t n_blocks = gpu_memory_blocks.size();
    size_t block_size = HALF_GB / sizeof(float);
    size_t total_elements = n_blocks * block_size;
    
    // Allocate and copy device pointers to GPU
    float **d_data_blocks;
    if (cudaMalloc(&d_data_blocks, n_blocks * sizeof(float*)) != cudaSuccess) {
        fprintf(stderr, "Failed to allocate device memory for data blocks\n");
        exit(1);
    }
    if (cudaMemcpy(d_data_blocks, gpu_memory_blocks.data(), n_blocks * sizeof(float*), cudaMemcpyHostToDevice) != cudaSuccess) {
        fprintf(stderr, "Failed to copy data blocks to device\n");
        exit(1);
    }
    
    while (true) {

        // Launch the kernel
        dim3 block(BLOCK_SIZE);
        dim3 grid((total_elements + BLOCK_SIZE - 1) / BLOCK_SIZE);
        gpu_torture_kernel<<<grid, block>>>(d_data_blocks, n_blocks, block_size);

        // Check for errors
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error launching kernel: %s\n", cudaGetErrorString(err));
            exit(1);
        } 

        // Wait for the kernel to complete
        err = cudaDeviceSynchronize();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error synchronizing devices: %s\n", cudaGetErrorString(err));
        } else {
            puts("GPU torture kernel finished");
        }
        
    }
}

/*******/
/* CPU */
/*******/

// Xorshift64 PRNG implementation
struct xorshift64_state {
    uint64_t a;
};

uint64_t xorshift64(struct xorshift64_state *state) {
    uint64_t x = state->a;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    return state->a = x;
}


char *alloc_mem(size_t n_bytes) {
    if (n_bytes == 0)
        return NULL;

    char *mem = (char *)calloc(1, n_bytes);
    if (!mem) {
        puts("malloc() failed."), exit(1);
    }

    for (size_t i = 0; i < n_bytes; i++)
        mem[i] = 0;

    printf("Allocated %.2f GB of memory\n", n_bytes / (double)ONE_GB);
    return mem;
}

typedef struct {
    char *mem;
    size_t size;
    uint64_t seed;
} ThreadArg;

void *cpu_task(void *arg) {
    ThreadArg *thread_arg = (ThreadArg *)arg;
    char *mem = thread_arg->mem;
    size_t size = thread_arg->size;
    struct xorshift64_state state = {thread_arg->seed};
    
    while (1) {
        for (size_t i = 0; i < size; i++) {
            size_t pos = xorshift64(&state) % size;
            char value = (char)(xorshift64(&state) & 0xFF);
            mem[pos] = value;
            // Force memory access
            volatile char dummy = mem[pos];
            (void)dummy;
        }
    }
    return NULL;
}

void torture_cpu(char *mem, size_t mem_size) {
    int numThreads = sysconf(_SC_NPROCESSORS_ONLN);
    pthread_t threads[numThreads];
    ThreadArg thread_args[numThreads];
    size_t chunk_size = mem_size / numThreads;

    // Use current time as a seed for the first thread
    uint64_t seed = (uint64_t)time(NULL);
    for (int t = 0; t < numThreads; t++) {
        thread_args[t].mem = mem + t * chunk_size;
        thread_args[t].size = (t == numThreads - 1) ? (mem_size - t * chunk_size) : chunk_size;
        thread_args[t].seed = seed + t; // Use a different seed for each thread
        int rc = pthread_create(&threads[t], NULL, cpu_task, &thread_args[t]);
        if (rc) {
            printf("ERROR; return code from pthread_create() is %d\n", rc);
            exit(1);
        }
    }

    for (int t = 0; t < numThreads; t++) {
        pthread_join(threads[t], NULL);
    }
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
        } else if (strncmp(argv[i], "--mem=", strlen("--mem=")) == 0) {
            char* mem_str = argv[i] + strlen("--mem=");
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

    char *allocated_mem = alloc_mem(mem_bytes);

    pthread_t gpu_thread;
    if (run_gpu) {
        // Initialize CUDA
        int deviceCount;
        cudaError_t err = cudaGetDeviceCount(&deviceCount);
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error getting device count: %s\n", cudaGetErrorString(err));
            return 1;
        }
        if (deviceCount == 0) {
            fprintf(stderr, "No CUDA devices found\n");
            return 1;
        }
        err = cudaSetDevice(0);
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA error setting device: %s\n", cudaGetErrorString(err));
            return 1;
        }

        // Create GPU torture thread
        if (pthread_create(&gpu_thread, NULL, launch_gpu_torture, NULL) != 0) {
            fprintf(stderr, "Failed to create GPU torture thread\n");
            return 1;
        }
    }

    if (run_cpu) {
        torture_cpu(allocated_mem, mem_bytes);
    }

    // Wait for GPU thread to finish if it was started
    if (run_gpu) {
        pthread_join(gpu_thread, NULL);
    }

    // Free allocated memory
    free(allocated_mem);

    return 0;
}
