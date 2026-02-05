#!/usr/bin/env python3
"""
Execute test commands and save output to .zig-cache/outputs/chxx.output files.
"""

import subprocess
from pathlib import Path


def execute_command(command: str) -> str:
    """
    Execute a command and return its output (stdout + stderr).
    Does not check for success/failure.
    """
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            cwd=Path(__file__).parent.parent,
        )
        output = result.stdout + result.stderr
        return output
    except Exception as e:
        return f"Error executing command: {e}\n"


def main():
    """
    Execute hardcoded test commands and save outputs.
    """
    # Hardcoded test commands for each chapter
    test_commands = {
        "ch02": "zig build ch02 && .\\zig-out\\bin\\ch02.exe .\\test_data\\luac.out",
        "ch03": "zig build ch03 && .\\zig-out\\bin\\ch03.exe .\\test_data\\luac.out",
        "ch04": "zig build ch04",
        "ch05": "zig build ch05",
        "ch06": "zig build ch06 && .\\zig-out\\bin\\ch06.exe .\\test_data\\sum.out",
        "ch07": "zig build ch07 && .\\zig-out\\bin\\ch07.exe .\\test_data\\test.out",
        "ch08": "zig build ch08 && .\\zig-out\\bin\\ch08.exe .\\test_data\\test08.luac",
        "ch09": "zig build ch09 && .\\zig-out\\bin\\ch09.exe .\\test_data\\luac.out",
        "ch10": "zig build ch10 && .\\zig-out\\bin\\ch10.exe .\\test_data\\test10.luac",
        "ch11": "zig build ch11 && .\\zig-out\\bin\\ch11.exe .\\test_data\\vector.luac",
        "ch12": "zig build ch12 && .\\zig-out\\bin\\ch12.exe .\\test_data\\test12.luac",
        "ch13": "zig build ch13 && .\\zig-out\\bin\\ch13.exe .\\test_data\\test13.luac",
        "ch14": "zig build ch14 && .\\zig-out\\bin\\ch14.exe .\\test_data\\test14_lexer.lua",
        "ch16": "zig build ch16 && .\\zig-out\\bin\\ch16.exe .\\test_data\\hello_world.lua",
    }

    # Clear previous outputs and ensure output directory exists
    output_dir = Path(__file__).parent.parent / ".zig-cache" / "outputs"
    if output_dir.exists():
        # Remove all files in the output directory
        for file in output_dir.glob("*.output"):
            file.unlink()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Execute commands and save outputs (in reverse order)
    for chapter, cmd in sorted(test_commands.items(), reverse=True):
        output_file = output_dir / f"{chapter}.output"

        print(f"Executing: {cmd}")
        print(f"Output to: {output_file}")

        # Execute command and capture output
        output = execute_command(cmd)

        # Write output to file
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(output)

        print("Done. Output saved.\n")


if __name__ == "__main__":
    main()
