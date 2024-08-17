#!/usr/bin/env python3

import sys
import argparse

def file_to_c_string(input_file):
    with open(input_file, 'r') as infile:
        content = infile.read()
    
    escaped_content = content.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    
    return f'"{escaped_content}"'

def file_to_python_string(input_file):
    with open(input_file, 'r') as infile:
        content = infile.read()
    
    escaped_content = content.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')
    
    return f"'{escaped_content}'"

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert a file to a C or Python string.")
    parser.add_argument("input_file", help="The input file to convert")
    parser.add_argument("-o", "--output", help="The output file (if not specified, print to stdout)")
    parser.add_argument("-p", "--python", action="store_true", help="Convert to Python string instead of C string")
    args = parser.parse_args()

    if args.python:
        result = file_to_python_string(args.input_file)
    else:
        result = file_to_c_string(args.input_file)

    if args.output:
        with open(args.output, 'w') as outfile:
            outfile.write(result)
        print(f"Converted {args.input_file} to {'Python' if args.python else 'C'} string in {args.output}")
    else:
        print(result)
