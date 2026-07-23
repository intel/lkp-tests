# How to run local monitor in a minimal environment
## Prepare lkp environment
```
[root@localhost ~]# dnf install gcc make git -y
[root@localhost ~]# git clone https://github.com/lkp/lkp-tests.git
[root@localhost lkp-tests]# make
[root@localhost ~]# export PATH=$PATH:"/usr/local/bin/"
```

## Install dependencies
```
[root@localhost ~]# dnf install perf procps which time psmisc -y
```

## Run job with monitor script and replace "sleep 10" to your own benchmark commands
```
# option "-s" could set the test name, and you could use "-o" to specify the result root directory

# job-scripts/monitor doesn't contain perf
[root@localhost ~]# lkp run-monitor -s sleep_10 monitor -- sleep 10
result_root: /lkp/result/mytest/sleep_10/localhost.localdomain/fedora/defconfig/gcc-8/5.2.0-rc3-8e44c7840479/0
2019-11-04 03:02:10  sleep 10
wait for background processes: 1870 1867 1879 1874 1888 zoneinfo slabinfo proc-vmstat buddyinfo meminfo

# job-scripts/monitor-perf contains 'perf-stat'
# you can choose other perf tools from lkp-tests/monitors/perf-*, then update both monitor-perf and monitor-perf.yaml
[root@localhost ~]# lkp run-monitor -s sleep_10 monitor-perf -- sleep 10
result_root: /lkp/result/mytest/sleep_10/localhost.localdomain/fedora/defconfig/gcc-8/5.2.0-rc3-8e44c7840479/1
2019-11-04 03:03:26  sleep 10
wait for background processes: 2203 2206 2210 2214 2219 2225 slabinfo zoneinfo buddyinfo proc-vmstat meminfo perf-stat
```

## Run monitor script without benchmark
```
# Run lkp run-monitor
[root@localhost ~]# lkp run-monitor monitor-perf

# Open another terminal to stop monitors
[root@localhost ~]# lkp stop-monitor
```

## Get the results
```
[root@localhost lkp-tests]# ls result_root -l
lrwxrwxrwx 1 root root 97 Nov  4 03:03 result_root -> /lkp/result/mytest/sleep_10/localhost.localdomain/fedora/defconfig/gcc-8/5.2.0-rc3-8e44c7840479/1
[root@localhost lkp-tests]# ls result_root/
buddyinfo.gz  env  job.sh  job.yaml  meminfo.gz  mytest  mytest.time  numa-meminfo.gz  numa-vmstat.gz  perf-stat.gz  proc-vmstat.gz  program_list  reproduce.sh  slabinfo  time  zoneinfo.gz
```
