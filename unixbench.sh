#!/bin/bash

timestamp=$(date +"%Y-%m-%d-%H%M")
CURRENT_DIR=$(cd $(dirname $0); pwd)
log_dir=$CURRENT_DIR/${timestamp}
mkdir -p ${log_dir}

read_log=${log_dir}/read_log
write_log=${log_dir}/write_log
copy_log=${log_dir}/copy_log

APP_DIR="/home/zhiyin/byte-unixbench/UnixBench"
APP_PATH="$APP_DIR/Run"

source /opt/rh/gcc-toolset-13/enable
cd $APP_DIR
make clean && make

if [[ -n $1 ]];then
  cores=$1
else
  cores=(1 2 4 8 16 32 64 128 full)
fi

for core in ${cores[*]};do
    if [[ $core == "full" ]];then
      cores_list=$(lscpu | grep "On-line CPU" | awk '{print $NF}')
    else
      cores_list=0-$((core-1))
    fi
    numactl -C $cores_list ./Run -c $core fsdisk-r fstime-r fsbuffer-r | grep -A 5 "Benchmark Run" >> $read_log
    numactl -C $cores_list ./Run -c $core fsdisk-w fstime-w fsbuffer-w | grep -A 5 "Benchmark Run" >> $write_log
    numactl -C $cores_list ./Run -c $core fsdisk fstime fsbuffer | grep -A 5 "Benchmark Run" >> $copy_log
done

cd -

