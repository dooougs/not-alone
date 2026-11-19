"""Renders every Not Alone sprite and icon in one go.

Run with the bpy module:   python image-builder/blender/render_all.py
(each model runs in its own process so scenes never leak into each other)
or render one model:       blender -b -P image-builder/blender/<model>.py
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = ["habitat.py", "iron_habitat.py", "outpost.py", "cloner.py",
          "command_tool.py"]

if __name__ == "__main__":
    for name in sys.argv[1:] or MODELS:
        print("==", name, flush=True)
        subprocess.run([sys.executable, os.path.join(HERE, name)], check=True)
