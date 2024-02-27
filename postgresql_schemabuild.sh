#!/bin/bash

echo "Building schema for $1. May take 5-10 mins...."
./hammerdbcli auto postgresql_schemabuild.tcl 2>&1 > build-output.txt
echo "Schema build complete"

