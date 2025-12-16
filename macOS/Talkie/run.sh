#!/bin/bash
# Delegate to consolidated run script
cd "$(dirname "$0")/.."
exec ./run.sh core "$@"
