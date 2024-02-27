#!/bin/bash

ROOT_DIR="/home/zhiyin/"
APP_DIR="$ROOT_DIR/postgres/"
export CLIENT_IP="192.168.10.180"
export SERVER_IP="192.168.10.106"

timestamp=$(date +"%Y-%m-%d-%H%M")
CURRENT_DIR=$(cd $(dirname $0); pwd)
log_dir=$CURRENT_DIR/${timestamp}
mkdir -p ${log_dir}

prepare_server(){
    if [[ ! -d $APP_DIR ]];then
      mkdir -p $ROOT_DIR; cd "/home/zhiyin/projects"
      git clone https://github.com/postgres/postgres.git
      git checkout -b v16.1 REL_16_1
      sudo yum install -y gcc gcc-c++ make flex bison perl-ExtUtils-Embed perl-ExtUtils-MakeMaker
      sudo yum install -y readline readline-devel zlib zlib-devel gettext gettext-devel openssl openssl-devel pam pam-devel libxml2 libxml2-devel libxslt libxslt-devel perl perl-devel libicu libicu-devel openldap openldap-devel python python-devel
      sudo yum install -y tcl-devel uuid-devel systemd-devel  net-tools llvm-devel clang krb5-devel libuuid-devel

      sudo groupadd postgres
      sudo useradd -g postgres postgres
      sudo passwd -d postgres
      sudo gpasswd -a zhiyin postgres
      mkdir –p /home/postgres/data
    fi

    source /opt/rh/gcc-toolset-13/enable
    cd $APP_DIR
    ./configure --prefix=/home/postgres/ --with-pgport=5432 --enable-debug --with-openssl --with-libxml --with-perl --with-python --with-tcl --with-pam --with-gssapi --enable-nls --with-libxslt --with-ldap --with-uuid=e2fs --with-icu
    make -j192 && make install
    cd -

    su - postgres -c "initdb; pg_ctl start"
}

prepare_client(){
  ssh zhiyin@$CLIENT_IP "sudo yum install -y postgresql sysbench"
  ssh zhiyin@$CLIENT_IP "sysbench --pgsql-host=$SERVER_IP  --pgsql-port=5432 --pgsql-user=postgres \
                          --pgsql-db=postgres --oltp-tables-count=16 --oltp-table-size=1000000 \
                          --report-interval=20 --threads=128 --db-driver=pgsql \
                          /usr/share/sysbench/tests/include/oltp_legacy/oltp.lua \
                          prepare"
}

cleanup(){
  ssh zhiyin@$CLIENT_IP "sysbench --pgsql-host=$SERVER_IP  --pgsql-port=5432 --pgsql-user=postgres \
                        --pgsql-db=postgres --oltp-tables-count=16 --oltp-table-size=1000000 \
                        --report-interval=20 --threads=128 --db-driver=pgsql \
                        /usr/share/sysbench/tests/include/oltp_legacy/oltp.lua \
                        cleanup"
}

function get_cpu_usage()
{
    sleep 120 

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

sysbench_test(){
  core_num=$1
  type=$2

  threads=$((32*core_num))
  if [[ $threads -gt 2048 ]]; then
    threads=2048
  fi
  ssh zhiyin@$CLIENT_IP "sysbench --db-driver=pgsql --pgsql-host=$SERVER_IP --pgsql-port=5432 \
                          --pgsql-db=postgres --pgsql-user=postgres --table-size=1000000 --tables=16 --threads=$threads \
                          --rand-type=uniform --report-interval=10 --time=120  --db-ps-mode=disable \
                          /usr/share/sysbench/oltp_read_only.lua run" 

  ssh zhiyin@$CLIENT_IP "sysbench --pgsql-host=$SERVER_IP --pgsql-port=5432 --pgsql-user=postgres \
                          --pgsql-db=postgres --oltp-tables-count=16 --oltp-table-size=1000000 --threads=$threads \
                          --oltp-test-mode=complex --report-interval=10 --rand-type=uniform \
                          --time=120 --percentile=99 --db-ps-mode=disable --db-driver=pgsql \
                          /usr/share/sysbench/tests/include/oltp_legacy/oltp.lua run" 
}

hammerdb_test(){
  type=$1
  core_num=$2

  for factor in 1 2 3 4 5 6 7 8
  do
    vu=$((factor*core_num))
    pg=$((vu*4))

    if [[ $vu -gt 128 ]];then
      return
    fi

    log_file=$log_dir/hammerdb.$type.$core_num.$vu.log
    summary_file=$log_dir/hammerdb.summary.log

    ssh zhiyin@$CLIENT_IP "cd /home/zhiyin/HammerDB-4.9; sed -ie 's/vuset vu .*$/vuset vu $vu/g' postgresql_test.tcl;"
    ssh zhiyin@$CLIENT_IP "cd /home/zhiyin/HammerDB-4.9; sed -ie 's/pg_num_vu .*$/pg_num_vu $vu/g' postgresql_test.tcl;"
    ssh zhiyin@$CLIENT_IP "cd /home/zhiyin/HammerDB-4.9; sed -ie 's/pg_count_ware .*$/pg_count_ware $pg/g' postgresql_test.tcl;"
    
    ssh zhiyin@$CLIENT_IP "cd /home/zhiyin/HammerDB-4.9; ./hammerdbcli auto postgresql_test.tcl" > $log_file &

    cpu_usage=$(get_cpu_usage 144 $((core+143)))
    wait

    result=$(grep "NOPM" $log_file)
    if [[ -z $result ]];then
      return
    fi

    nopm=$(echo $result | awk '{print $7}')
    tpm=$(echo $result | awk '{print $10}')
    echo "$type $core_num $vu $nopm $tpm $cpu_usage" >> $log_dir/hammerdb.summary.log
  done
}


if [[ -n $1 ]];then
  cores=$1
else
  cores=(1 2 4 8 16 32 64 128)
fi


echo "type core_num vu nopm tpm cpu_usage" > $log_dir/hammerdb.summary.log
# echo "case queries trans avg 95th" > $log_dir/sysbench.summary.log

for type in v0 v1
do
    source /opt/rh/gcc-toolset-13/enable
    cd $APP_DIR
    cp $CURRENT_DIR/$type.lwlock.c $APP_DIR/src/backend/storage/lmgr/lwlock.c
    source /opt/rh/gcc-toolset-13/enable
    make -j192 && make install
    cd -

    for core in ${cores[*]};do
        if [[ $core == "full" ]];then
          core=$(lscpu | grep "^CPU(s):" | awk '{print $NF}')
          cores_list=$(lscpu | grep "On-line CPU" | awk '{print $NF}')
        else
          cores_list=144-$((core+143))
        fi

        # shared_buffers=$((factor*3/4))
        # wal_buffers=$((factor*64))
        # effective_cache_size=$((factor*3/4))
        # sudo sed -ie 's/^shared_buffers =.*;$/worker_processes = $cores;/g' /home/postgres/data/postgresql.conf
        # sed -ie 's/vu .*$/vu 128/g' postgresql_test.tcl
        su - postgres -c "numactl -C $cores_list pg_ctl restart"
        # sysbench_test $core $type
        hammerdb_test $type $core
    done
done

