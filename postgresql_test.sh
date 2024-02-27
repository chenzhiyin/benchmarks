#!/bin/bash

echo "Starting performance run for $1 for {"$2"}..."
./hammerdbcli auto postgresql_test.tcl 2>&1 > run-output.txt
echo "Performance run complete"

