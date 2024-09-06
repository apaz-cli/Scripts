#!/bin/bash

# Check if nvcc is available
if command -v nvcc &> /dev/null
then
    echo "NVCC found, compiling with CUDA support"
    nvcc -O3 -o torture torture.cu -lpthread
else
    echo "NVCC not found, compiling without CUDA support"
    cc -x c -O3 -o torture torture.cu -lpthread -lm
fi

echo "Build complete. Run ./torture to execute the program."
