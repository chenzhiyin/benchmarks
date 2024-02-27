#!/bin/bash

ROOT_DIR="/home/zhiyin/"
APP_DIR="$ROOT_DIR/postgres/"
PG_DATA_BACKUP_BASE="/home/postgres/"
PG_DATA_BASE="/home/postgres/"
CURRENT_DIR=$(cd $(dirname $0); pwd)

export SERVER_IP=127.0.0.1

function get_cpu_usage()
{
    sleep 180 

    min_cpus=$1
    max_cpus=$2
    total_cpus=$((max_cpus-min_cpus+1))

    start_idle=()
    start_total=()
    cpu_rate=()

    for((i=${min_cpus};i<=${max_cpus};i++))
    {
        start=$(cat /proc/stat | grep "cpu$i" | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
        start_idle[$i]=$(echo ${start} | awk '{print $4}')
        start_total[$i]=$(echo ${start} | awk '{printf "%.f",$1+$2+$3+$4+$5+$6+$7}')
    }

    sleep 60
    cpu_idle=0
    cpu_usage=0
    for((i=${min_cpus};i<=${max_cpus};i++))
    {
        end=$(cat /proc/stat | grep "cpu$i" | awk '{print $2" "$3" "$4" "$5" "$6" "$7" "$8}')
        end_idle=$(echo ${end} | awk '{print $4}')
        end_total=$(echo ${end} | awk '{printf "%.f",$1+$2+$3+$4+$5+$6+$7}')
        idle=`expr ${end_idle} - ${start_idle[$i]}`
        total=`expr ${end_total} - ${start_total[$i]}`
        idle_normal=`expr ${idle} \* 100`
        cpu_usage=$(echo "${idle_normal} ${total} ${cpu_usage}" | awk '{printf("%.3f\n",$1/$2+$3)}')
    }
    echo "${cpu_usage} ${total_cpus} 100" | awk '{printf("%.3f\n",$3-$1/$2)}'
}

stop_server(){
  is_running=$(su - postgres -c "pg_ctl status" | grep PID)
  while [[ -n $is_running ]];do
    if ! su - postgres -c "pg_ctl stop";then
      sleep 120
    fi
    is_running=$(su - postgres -c "pg_ctl status" | grep PID)
  done
}

start_server(){
  if [[ -z $1 ]];then
    cmd="pg_ctl start"
  else
    cmd="numactl -C $1 pg_ctl start"
  fi

  is_running=$(su - postgres -c "pg_ctl status" | grep PID)
  while [[ -z $is_running ]];do
    su - postgres -c "${cmd}"
    sleep 3
    is_running=$(su - postgres -c "pg_ctl status" | grep PID)
  done
}

db_create(){
    pg_count_ware=$1
    if [[ -d ${PG_DATA_BACKUP_BASE}/$pg_count_ware ]];then
      echo "db backup data exist!!! skip..."
      return
    fi

    # delete db 
    stop_server
    sudo rm -rf ${PG_DATA_BASE}/data
    su - postgres -c "initdb"
    su - postgres -c "cp /home/postgres/postgresql.conf ${PG_DATA_BASE}/data/"
    su - postgres -c "cp /home/postgres/pg_hba.conf ${PG_DATA_BASE}/data/"

    # create hammerdb
    start_server
    cd /home/zhiyin/HammerDB-4.9/
    sed -ie "s/pg_count_ware .*$/pg_count_ware $pg_count_ware/g" $CURRENT_DIR/postgresql_schemabuild.tcl
    if [[ $pg_count_ware -gt 288 ]];then
      vu=288
    else
      vu=$pg_count_ware
    fi
    sed -ie "s/pg_num_vu .*$/pg_num_vu $vu/g" $CURRENT_DIR/postgresql_schemabuild.tcl

    ./hammerdbcli auto  $CURRENT_DIR/postgresql_schemabuild.tcl
    sleep 30
    cd -

    # stop server
    stop_server

    # backup server db data
    sudo rm -rf ${PG_DATA_BACKUP_BASE}/$pg_count_ware
    su - postgres -c "mv ${PG_DATA_BASE}/data ${PG_DATA_BACKUP_BASE}/$pg_count_ware"
}

install_server(){
  if [[ -n $1 ]];then
    cp $CURRENT_DIR/$1.lwlock.c $APP_DIR/src/backend/storage/lmgr/lwlock.c
  fi

  source /opt/rh/gcc-toolset-13/enable > /dev/null
  cd $APP_DIR; 
  if ! (make -j256 > /dev/null && make install > /dev/null) ;then
    echo "compiled pg failed"
    exit 1
  fi
  cd -
}

type=$1
core_num=$2
vu_factor=$3

# server
stop_server
install_server $type

sudo rm -rf ${PG_DATA_BASE}/data
su - postgres -c "cp -rf ${PG_DATA_BACKUP_BASE}/$((core_num)) ${PG_DATA_BASE}/data"
if [[ -n $4 ]];then
  conf_file=$4
  su - postgres -c "cp /home/postgres/$conf_file ${PG_DATA_BASE}/data/postgresql.conf"
fi

start_server 144-$((core_num+143))

# client
vu=$((vu_factor*core_num))
sed -ie "s/vuset vu .*$/vuset vu $vu/g" $CURRENT_DIR/postgresql_test.tcl
cd /home/zhiyin/HammerDB-4.9/
numactl -C 0-143 ./hammerdbcli auto $CURRENT_DIR/postgresql_test.tcl > $CURRENT_DIR/detail.log &
cd -


# perf data
cpu_usage_value=$(get_cpu_usage 144 $((core_num+143)))

pid=$(ps -ef | grep postgresql_test.tcl | grep -v grep | awk '{print $2}')
while [[ -n $pid ]];do
  if grep "NOPM"  $CURRENT_DIR/detail.log;then
    kill -9 $pid
  fi
  sleep 3
  pid=$(ps -ef | grep postgresql_test.tcl | grep -v grep | awk '{print $2}')
done

wait

result=$(grep "NOPM" $CURRENT_DIR/detail.log)
if [[ -z $result ]];then
  return
fi

nopm=$(echo $result | awk '{print $7}')
tpm=$(echo $result | awk '{print $10}')

echo "$type $core_num $vu $pg_count_ware $nopm $tpm $cpu_usage_value"
