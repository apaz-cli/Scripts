#!/bin/bash

set -e

# Create a temporary directory for testing
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Copy secrets.c to the test directory
cp ~/git/Scripts/secrets.c .

# Create some test files
echo "This is file1" > file1.txt
echo "This is file2" > file2.txt
mkdir subdir
echo "This is file3 in subdir" > subdir/file3.txt

# Create an archive
./secrets.c create test_archive.bin "*.txt subdir/*.txt" "password123"

# Clean up the original files
rm -rf file1.txt file2.txt subdir

# Extract the archive
mkdir extracted
./secrets.c extract test_archive.bin extracted "password123"

# Verify the extracted files
diff file1.txt extracted/file1.txt
diff file2.txt extracted/file2.txt
diff subdir/file3.txt extracted/subdir/file3.txt

echo "All tests passed successfully!"

# Clean up
cd ..
rm -rf "$TEST_DIR"
