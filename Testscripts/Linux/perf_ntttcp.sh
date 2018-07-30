#!/bin/bash
#######################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
#######################################################################

#######################################################################
#
# perf_ntttcp.sh
# Description:
#    Download and run ntttcp network performance tests.
#    This script needs to be run on client VM.
#
#######################################################################

CONSTANTS_FILE="./constants.sh"
ICA_TESTRUNNING="TestRunning"           # The test is running
ICA_TESTCOMPLETED="TestCompleted"       # The test completed successfully
ICA_TESTABORTED="TestAborted"           # Error during the setup of the test
ICA_TESTFAILED="TestFailed"             # Error occurred during the test
touch ./ntttcpTest.log

LogMsg()
{
	echo `date "+%b %d %Y %T"` : "${1}"    # Add the time stamp to the log message
	echo "${1}" >> ./ntttcpTest.log
}
UpdateTestState()
{
	echo "${1}" > ./state.txt
}

if [ -e ${CONSTANTS_FILE} ]; then
	source ${CONSTANTS_FILE}
else
	errMsg="Error: missing ${CONSTANTS_FILE} file"
	LogMsg "${errMsg}"
	UpdateTestState $ICA_TESTABORTED
	exit 10
fi

log_folder="ntttcp-${testType}-test-logs"
max_server_threads=64

InstallNTTTCP()
{
	DISTRO=`grep -ihs "ubuntu\|Suse\|Fedora\|Debian\|CentOS\|Red Hat Enterprise Linux\|clear-linux-os" /etc/{issue,*release,*version} /usr/lib/os-release`
    LogMsg "Configuring ${1} for ntttcp ${testType} test..."
	if [[ $DISTRO =~ "Ubuntu" ]];
	then
		LogMsg "Detected UBUNTU"
		ssh ${1} "until dpkg --force-all --configure -a; sleep 10; do echo 'Trying again...'; done"
		ssh ${1} "apt-get update"
		ssh ${1} "apt-get -y install libaio1 sysstat git bc make gcc dstat psmisc"
	elif [[ $DISTRO =~ "Red Hat Enterprise Linux Server release 6" ]];
	then
		LogMsg "Detected Redhat 6.x"
		ssh ${1} "rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
		ssh ${1} "yum -y --nogpgcheck install libaio1 sysstat git bc make gcc dstat psmisc"
		ssh ${1} "yum -y --nogpgcheck install gcc-c++"
		ssh ${1} "wget http://ftp.heanet.ie/mirrors/gnu/libc/glibc-2.14.1.tar.gz"
		ssh ${1} "tar xvf glibc-2.14.1.tar.gz"
		ssh ${1} "mv glibc-2.14.1 glibc-2.14 && cd glibc-2.14 && mkdir build && cd build && ../configure --prefix=/opt/glibc-2.14 && make && make install && export LD_LIBRARY_PATH=/opt/glibc-2.14/lib:$LD_LIBRARY_PATH"
	elif [[ $DISTRO =~ "Red Hat Enterprise Linux Server release 7" ]];
	then
		LogMsg "Detected Redhat 7.x"
		ssh ${1} "rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
		ssh ${1} "yum -y --nogpgcheck install libaio1 sysstat git bc make gcc dstat psmisc"
	elif [[ $DISTRO =~ "CentOS Linux release 6" ]] || [[ $DISTRO =~ "CentOS release 6" ]];
	then
		LogMsg "Detected CentOS 6.x"
		ssh ${1} "rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
		ssh ${1} "yum -y --nogpgcheck install libaio1 sysstat git bc make gcc dstat psmisc"
		ssh ${1} "yum -y --nogpgcheck install gcc-c++"
	elif [[ $DISTRO =~ "CentOS Linux release 7" ]];
	then
		LogMsg "Detected CentOS 7.x"
		ssh ${1} "rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
		ssh ${1} "yum -y --nogpgcheck install libaio1 sysstat git bc make gcc dstat psmisc"
	elif [[ $DISTRO =~ "SUSE Linux Enterprise Server" ]];
	then
		LogMsg "Detected SLES"
		if [[ $DISTRO =~ "SUSE Linux Enterprise Server 12" ]];
		then
			LogMsg "Detected SLES 12"
			repositoryUrl="https://download.opensuse.org/repositories/network:utilities/SLE_12_SP3/network:utilities.repo"
		elif [[ $DISTRO =~ "SUSE Linux Enterprise Server 15" ]];
		then
			LogMsg "Detected SLES 15"
			repositoryUrl="https://download.opensuse.org/repositories/network:utilities/SLE_15/network:utilities.repo"
		fi
		ssh ${1} "zypper addrepo ${repositoryUrl}"
		ssh ${1} "zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys refresh"
		ssh ${1} "zypper --no-gpg-checks --non-interactive --gpg-auto-import-keys install sysstat git bc make gcc dstat psmisc"
	elif [[ $DISTRO =~ "clear-linux-os" ]];
	then
		LogMsg "Detected Clear Linux OS. Installing required packages"
		ssh ${1} "swupd bundle-add dev-utils-dev sysadmin-basic performance-tools os-testsuite-phoronix network-basic openssh-server dev-utils os-core os-core-dev"
		ssh ${1} "iptables -F"
	else
		LogMsg "Unknown Distro"
		UpdateTestState "TestAborted"
		UpdateSummary "Unknown Distro, test aborted"
		exit 1
	fi
	ssh ${1} "wget https://github.com/Microsoft/ntttcp-for-linux/archive/v1.3.4.tar.gz"
	ssh ${1} "tar xvzf v1.3.4.tar.gz"
	ssh ${1} "cd ntttcp-for-linux-1.3.4/src/ && make && make install"
	if [ $? -ne 0 ]; then
		LogMsg "Error: ntttcp installation failed.."
		UpdateTestState $ICA_TESTABORTED
		exit 1
	else
		LogMsg "NTTTCP installed successfully"
		ssh ${1} "cp ntttcp-for-linux-1.3.4/src/ntttcp ."
	fi
	ssh ${1} "rm -rf lagscope"
	ssh ${1} "git clone https://github.com/Microsoft/lagscope"
	ssh ${1} "cd lagscope/src && make && make install"
	if [ $? -ne 0 ]; then
		LogMsg "Error: ntttcp installation failed.."
		UpdateTestState $ICA_TESTABORTED
		exit 1
	else
		LogMsg "lagscope installed successfully"
	fi
	ssh ${1} "iptables -F"
	ssh ${1} "sysctl -w net.core.rmem_max=67108864; sysctl -w net.core.rmem_default=67108864; sysctl -w net.core.wmem_default=67108864; sysctl -w net.core.wmem_max=67108864"
}

runNtttcp()
{
	i=0
	ssh ${server} "mkdir -p $log_folder"
	ssh ${client} "mkdir -p $log_folder"
	LogMsg "$server $client $testConnections"
	result_file="${log_folder}/report.csv"
	echo "TestConnections,TxThroughputInGbps,RxThroughputInGbps,TxCycles/Byte,RxCycles/Byte,AvgLatency" > $result_file

	for current_test_threads in $testConnections; do
		if [[ $current_test_threads -lt $max_server_threads ]];
		then
			num_threads_P=$current_test_threads
			num_threads_n=1
		else
			num_threads_P=$max_server_threads
			num_threads_n=$(($current_test_threads/$num_threads_P))
		fi
		
		throughput=0
		cyclesperbytes=0
		avglatency=0

		LogMsg "============================================="
		LogMsg "Running ${testType} Test: $current_test_threads connections : $num_threads_P X $num_threads_n"
		LogMsg "============================================="
		
		if [[ $testType == "udp" ]] || [[ $testType == "UDP" ]] || [[ $testType == "Udp" ]];
		then
			LogMsg "Test running in ${testType} mode"
			txlogFile="${testType}-${bufferLength}-sender-p${num_threads_P}X${num_threads_n}.log"
			rxlogFile="${testType}-${bufferLength}-receiver-p${num_threads_P}X${num_threads_n}.log"
            serverNTTTCPCmd="ulimit -n 204800 && ntttcp -P ${num_threads_P} -t ${testDuration} -e -u -b ${bufferLength}"
			clientNTTTCPCmd="ntttcp -s${server} -P ${num_threads_P} -n ${num_threads_n} -t ${testDuration} -u -b ${bufferLength}"
		else
			LogMsg "Test running in ${testType} mode"
			txlogFile="${testType}-sender-p${num_threads_P}X${num_threads_n}.log"
			rxlogFile="${testType}-receiver-p${num_threads_P}X${num_threads_n}.log"
            serverNTTTCPCmd="ulimit -n 204800 && ntttcp -P ${num_threads_P} -t ${testDuration} -e"
            clientNTTTCPCmd="ntttcp -s${server} -P ${num_threads_P} -n ${num_threads_n} -t ${testDuration}"
            ssh ${server} "for i in {1..$testDuration}; do ss -ta | grep ESTA | grep -v ssh | wc -l >> ./$log_folder/tcp-connections-p${num_threads_P}X${num_threads_n}.log; sleep 1; done" &
		fi
        
        tx_ntttcp_log_file="$log_folder/ntttcp-${txlogFile}"
        tx_lagscope_log_file="$log_folder/lagscope-${txlogFile}"
        rx_ntttcp_log_file="$log_folder/ntttcp-${rxlogFile}"

        ssh ${server} "pkill -f ntttcp"
        LogMsg "$serverNTTTCPCmd > ./$log_folder/ntttcp-${rxlogFile}"
        ssh ${server} "${serverNTTTCPCmd}" > "./$log_folder/ntttcp-${rxlogFile}" &

		ssh ${server} "pkill -f lagscope"
        ssh ${server} "lagscope -r" &

		ssh ${server} "pkill -f dstat"
		ssh ${server} "dstat -dam" > "./$log_folder/dstat-${rxlogFile}" &

		ssh ${server} "pkill -f mpstat"
		ssh ${server} "mpstat -P ALL 1 ${testDuration}" > "./$log_folder/mpstat-${rxlogFile}" &

		ulimit -n 204800
		sleep 2
		sar -n DEV 1 ${testDuration} > "./$log_folder/sar-${txlogFile}" &
		dstat -dam > "./$log_folder/dstat-${txlogFile}" &
		mpstat -P ALL 1 ${testDuration} > "./$log_folder/mpstat-${txlogFile}" &
		lagscope -s${server} -t ${testDuration} -V > "./$log_folder/lagscope-${txlogFile}" &
        LogMsg "${clientNTTTCPCmd} > ./${log_folder}/ntttcp-${txlogFile}"
        $clientNTTTCPCmd > "./${log_folder}/ntttcp-${txlogFile}"

		LogMsg "Parsing results for $current_test_threads connections"
        sleep 10
		txThroughput=$(cat $tx_ntttcp_log_file | grep throughput | tail -1 | tr ":" " " | awk '{ print $NF }')
		if [[ $txThroughput =~ "Gbps" ]];
		then
			txThroughput=$(echo $txThroughput | sed 's/Gbps//')
		elif [[ $txThroughput =~ "Mbps" ]];
		then
			$(echo "scale=5; $txThroughput/1000" | bc)
		else
			LogMsg "throughput in $txThroughput"
		fi

        rxThroughput=$(cat $rx_ntttcp_log_file | grep throughput | tail -1 | tr ":" " " | awk '{ print $NF }')
		if [[ $rxThroughput =~ "Gbps" ]];
		then
			rxThroughput=$(echo $rxThroughput | sed 's/Gbps//')
		elif [[ $rxThroughput =~ "Mbps" ]];
		then
			$(echo "scale=5; $rxThroughput/1000" | bc)
		else
			LogMsg "throughput in $rxThroughput"
		fi

		txCyclesperbytes=$(cat $tx_ntttcp_log_file | grep cycles/byte | tr ":" " " | awk '{ print $NF }')
		Avglatency=$(cat $tx_lagscope_log_file | grep Average | sed 's/.* //' | sed 's/us//')
        rxCyclesperbytes=$(cat $rx_ntttcp_log_file | grep cycles/byte | tr ":" " " | awk '{ print $NF }')
	
		LogMsg "Throughput in Gbps : TX : $txThroughput : RX : $rxThroughput"
		LogMsg "Cycles/Byte : TX: $txCyclesperbytes : RX: $rxCyclesperbytes"
		LogMsg "AvgLaentcy in us : TX : $Avglatency "
		echo "$current_test_threads,$txThroughput,$rxThroughput,$txCyclesperbytes,$rxCyclesperbytes,$Avglatency" >> $result_file
		LogMsg "current test finished. wait for next one... "
		i=$(($i + 1))
		sleep 5
	done
}

if [ ! ${server} ]; then
	errMsg="Please add/provide value for server in constants.sh. server=<server ip>"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi
if [ ! ${client} ]; then
	errMsg="Please add/provide value for client in constants.sh. client=<client ip>"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

if [ ! ${testDuration} ]; then
	errMsg="Please add/provide value for testDuration in constants.sh. testDuration=60"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

if [ ! ${nicName} ]; then
	errMsg="Please add/provide value for nicName in constants.sh. nicName=eth0/bond0"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

#Make & build ntttcp on client and server Machine
LogMsg "Configuring client ${client}..."
InstallNTTTCP ${client}

LogMsg "Configuring server ${server}..."
InstallNTTTCP ${server}

LogMsg "Now running NTTTCP ${testType} test"
runNtttcp

column -s, -t $result_file > ./$log_folder/report.log
ssh root@${client} "cp ntttcp-${testType}-test-logs/* ."
cat report.log
UpdateTestState ICA_TESTCOMPLETED