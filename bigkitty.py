#!/bin/env python3

import sys
import subprocess
from time import sleep
import os

"""
if [ ! "$1" = "" ]; then
  if ! python -c "import sys; int(sys.argv[1])" "$1" 2>/dev/null; then echo "Argument must be an integer."; exit 1; fi
  SIZE="$1"
else
  SIZE="37.5"
fi
"""

reset = True
if len(sys.argv) > 1 and sys.argv[1] == "-r":
    SIZE = "15"
    reset = False
if len(sys.argv) > 1:
    try:
        int(sys.argv[1])
        SIZE = sys.argv[1]
    except ValueError:
        print("Argument must be an integer.")
        exit(1)
else:
    SIZE = "37.5"

HOME = os.path.expanduser("~")
ORIGINAL = f"{HOME}/.config/kitty/kitty.conf"
TEMP = f"{HOME}/.config/kitty/kitty.conf.tmp"

os.rename(ORIGINAL, TEMP)
with open(TEMP) as temp:
    with open(ORIGINAL, "w") as original:
        for line in temp:
            # If it's the font_size line, replace it.
            if line.startswith("font_size"):
                original.write(f"font_size {SIZE}\n")
            else:
                original.write(line)

subp = subprocess.Popen(["nohup", "kitty", "&"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    if reset:
        sleep(2)
        os.rename(TEMP, ORIGINAL)
        # race condition
        reset = False
    subp.wait()
except:
    pass
finally:
    if reset:
        try:
            os.rename(TEMP, ORIGINAL)
        except FileNotFoundError:
            pass # handle race condition




