#!/bin/tclsh
# maintainer: Khun Ban

set tmpdir /home/zhiyin/
puts "SETTING CONFIGURATION"
dbset db pg

dbset bm TPC-C

diset connection pg_host 127.0.0.1

diset conection pg_port 5432

diset tpcc pg_count_ware 1024

diset tpcc pg_num_vu 288

diset tpcc pg_superuser postgres


diset tpcc pg_storedprocs false

vuset logtotemp 1

vuset unique 1

puts "SCHEMA BUILD STARTED"
buildschema
puts "SCHEMA BUILD COMPLETED"


