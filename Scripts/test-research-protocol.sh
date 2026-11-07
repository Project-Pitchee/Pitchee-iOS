#!/bin/sh
set -eu
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_directory=$(dirname "$script_directory")
cd "$project_directory"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/Research -p 'test_research_protocol.py' -v
