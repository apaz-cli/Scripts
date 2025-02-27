#!/bin/bash

# Specify the file
FILE="$1"

# Extract the first 8 bytes and convert them to a decimal integer
HEADER_LENGTH=$(dd "if=$FILE" bs=1 count=8 2>/dev/null | od -An -vtu8)

# Extract the metadata, starting from the 9th byte
dd "if=$FILE" bs=1 skip=8 "count=$HEADER_LENGTH" 2>/dev/null | jq
