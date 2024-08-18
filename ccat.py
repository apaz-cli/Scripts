#!/usr/bin/env python3

import argparse
import sys
from pygments import highlight
from pygments.lexers import get_lexer_for_filename
from pygments.formatters import TerminalFormatter

def cat_highlighted(file_path):
    try:
        with open(file_path, 'r') as file:
            content = file.read()
        lexer = get_lexer_for_filename(file_path)
        highlighted = highlight(content, lexer, TerminalFormatter())
        print(highlighted)
    except FileNotFoundError:
        print(f"Error: File '{file_path}' not found.", file=sys.stderr)
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
