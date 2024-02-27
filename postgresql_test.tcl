#!/bin/tclsh

set tmpdir /home/zhiyin/
puts "SETTING CONFIGURATION"
dbset db pg

diset connection pg_host 127.0.0.1

diset connection pg_port 5432

diset tpcc pg_superuser postgres


diset tpcc pg_vacuum true

diset tpcc pg_driver timed

diset tpcc pg_rampup 2

diset tpcc pg_duration 3

diset tpcc pg_storedprocs false

vuset logtotemp 1

vuset unique 1

loadscript

puts "TEST STARTED"

vuset vu 4096

vucreate

vurun

runtimer 300

vudestroy


tcstop

puts "TEST COMPLETE"

