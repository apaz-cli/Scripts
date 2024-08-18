#!/usr/bin/env python3

import argparse
import sys
import os
from pygments import highlight
from pygments.lexers import get_lexer_for_filename, guess_lexer, get_lexer_by_name
from pygments.formatters import TerminalFormatter
from pygments.util import ClassNotFound

def get_shebang_lexer(file_path):
    with open(file_path, 'r') as file:
        content = file.read()
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if i == 0 and line.startswith('#!'):
                if 'python' in line:
                    return get_lexer_by_name('python')
                elif 'bash' in line or 'sh' in line:
                    return get_lexer_by_name('bash')
            if line.strip() == '#if 0' and i + 1 < len(lines):
                next_line = lines[i + 1].strip()
                if all(component in next_line for component in ['mktemp -d', 'cc', '-x c', '"$0"']):
                    return get_lexer_by_name('c')
    return None

def cat_highlighted(file_path):
    try:
        with open(file_path, 'r') as file:
            content = file.read()
        
        lexer = None
        try:
            lexer = get_lexer_for_filename(file_path)
        except ClassNotFound:
            lexer = get_shebang_lexer(file_path)
        
        if lexer is None:
            lexer = guess_lexer(content)
        
        highlighted = highlight(content, lexer, TerminalFormatter())
        print(highlighted)
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.", file=sys.stderr)
    except PermissionError:
        print(f"Error: Permission denied for file '{file_path}'.", file=sys.stderr)
    except IsADirectoryError:
        print(f"Error: '{file_path}' is a directory, not a file.", file=sys.stderr)
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)

def main():
    parser = argparse.ArgumentParser(description="Cat files with syntax highlighting.")
    parser.add_argument('files', nargs='+', help='File(s) to display')
    args = parser.parse_args()

    for file_path in args.files:
        cat_highlighted(file_path)

if __name__ == "__main__":
    main()
