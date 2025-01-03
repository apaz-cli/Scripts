#!/usr/bin/env python3
import os
import re
import subprocess

def is_shell_script(filepath):
    try:
        result = subprocess.run(['file', filepath], capture_output=True, text=True)
        return 'shell script' in result.stdout.lower()
    except:
        return False

def quote_unquoted_args(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Replace $@ that's not already quoted
    # Negative lookbehind for quote, negative lookahead for quote
    pattern = r'(?<!["\'])\$@(?!["\'"])'
    modified = re.sub(pattern, '"$@"', content)
    
    if modified != content:
        with open(filepath, 'w') as f:
            f.write(modified)

def main():
    for root, _, files in os.walk('.'):
        for file in files:
            filepath = os.path.join(root, file)
            if is_shell_script(filepath):
                quote_unquoted_args(filepath)

if __name__ == '__main__':
    main()
