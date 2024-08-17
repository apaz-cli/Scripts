#!/usr/bin/env python3

import sys

def file_to_c_string(input_file):
    with open(input_file, 'r') as infile:
        content = infile.read()
    
    escaped_content = content.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    
    return f'"{escaped_content}"'

if __name__ == "__main__":
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("Usage: python tocstring.py <input_file> [output_file]")
        sys.exit(1)
    
    input_file = sys.argv[1]
    c_string = file_to_c_string(input_file)
    
    if len(sys.argv) == 3:
        output_file = sys.argv[2]
        with open(output_file, 'w') as outfile:
            outfile.write(c_string)
        print(f"Converted {input_file} to C string in {output_file}")
    else:
        print(c_string)
