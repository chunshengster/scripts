#!/bin/bash
# Author:"Wang Chunsheng"<chunshengster@gmail.com>
# Date: 2013.04.25
# usage example : ./$0 -nic em1

set -x

#for grep nic card patten,you can change this one to meet you system envement!
NIC_PATTERN='em\|eth\|p1\|wlan'
RX_PATTERN='rx'

LS='/bin/ls'
CAT='/bin/cat'
GREP='/bin/grep'
PS='/bin/ps'
#TODO:add support ubuntu system stop a service
#this time only support Redhat  system 
SERVICE='/sbin/service'
CHKCONFIG='/sbin/chkconfig'

#
#TODO:this will be a param which get value from commond line with opt -di
DISABLE_IRQBALANCE='no'

SYSNET_PATH='/sys/class/net'
QUEUE_PATH='queues'
RSF_ENTRIES_FILE="/proc/sys/net/core/rps_sock_flow_entries"
RSF_ENTRIES_NUM=32768

CPU_IDS=''
CPU_COUNT=0
ALL_USED_INTERFACE=''
SMP_AFFINITY_INF=''
RPS_RFS_INF=''
RPS_RFS_MASK=''

function check_interface_inuse(){
	local updown=$($CAT "$SYSNET_PATH/$1/operstate")
	if [ $? -eq 0 ]; then
		if [ $updown == 'up' ]; then
			return 0
		else
			return 1
		fi
	fi
	return 1
}

function get_all_inused_interfaces(){
	local allInterFaces=$($LS $SYSNET_PATH | $GREP $NIC_PATTERN)
	
	local len_t=${#allInterFaces}
	
	if [ $len_t -lt 1 ];then
			return 1
	fi
	
	for inf_t in $allInterFaces;do
		#echo $inf_t
		check_interface_inuse "$inf_t"
		if [ $? -eq 0 ]; then
			#echo $inf_t
			ALL_USED_INTERFACE=$ALL_USED_INTERFACE" "$inf_t
		fi
	done
	#echo $ALL_USED_INTERFACE
	return 0
}


# check if smp affinity support,if not,will use rps/rfs future
function check_smp_affinity_support(){
	if [ -z $1 ];then
		return 1
	fi
	local nic_t_queue_count=$($LS "$SYSNET_PATH/$1/$QUEUE_PATH" | $GREP -c $RX_PATTERN)
	if [ $nic_t_queue_count -gt 1 ]; then
		SMP_AFFINITY_INF=$SMP_AFFINITY_INF" "$1
	else
		RPS_RFS_INF=$RPS_RFS_INF" "$1
	fi
	return 1
}


# check for irqbalance running
# if $DISABLE_IRQBALANCE == 'yes' then disable irqbalance service
function check_irqbalance_on(){
	IRQBALANCE_ON=$($PS ax | $GREP -v grep | $GREP -q irqbalance; echo $?)
	if [ "$IRQBALANCE_ON" == "0" ] ; then
	        
	        if [ $DISABLE_IRQBALANCE == 'yes' ]; then
	        	$SERVICE irqbalance stop
	        	if [ $? -eq 0 ]; then 
	        		return 0
	        	fi
	        fi
	        echo " WARNING: irqbalance is running and will"
	        echo "          likely override this script's affinitization."
	        echo "          Please stop the irqbalance service and/or execute"
	        echo "          'killall irqbalance'" 
	fi
	return 1
}

function get_cpuinfo(){
	CPU_IDS=$($CAT /proc/cpuinfo | $GREP processor | $GREP -v grep | cut -d: -f 2)	
	CPU_COUNT=$(echo $CPU_IDS | wc -w)
	if [ $CPU_COUNT -lt 1 ];then
		return 1
	fi
	return 0
}

function get_rpfs_affinity_mask(){
	local t=$(($CPU_COUNT/4))
	if [ $t -lt 1 ]; then
		return 1
	fi
	
	for i in $(seq $t); do
		RPS_RFS_MASK=$RPS_RFS_MASK'f'
	done
	
	local ok_t=$(echo $RPS_RFS_MASK | $GREP -q 'f'; echo $?)
	return $ok_t				
}

#TODO:refactor this function
function do_rpfs_enable(){
	nic_dev=$1
	if [ -f SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_cpus ]; then
		echo $RPS_RFS_MASK > SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_cpus
	else
		return 1
	fi
	if [ -f SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_flow_cnt ]; then
		echo 4096 > SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_flow_cnt
	else
		return 1
	return 0	
}

function do_rsf_entries_enable(){
	rsf_entries=$($CAT $RSF_ENTRIES_FILE)
	if [ $rsf_entries -eq $RSF_ENTRIES_NUM ]; then
		return 0
	else
		echo $RSF_ENTRIES_NUM > $RSF_ENTRIES_FILE
	return 0	
}

function do_smpaffinity_enable(){
	nic_dev=$1
	softIrqs=$(cat /proc/interrupts | $GREP $nic_dev | tr -s " " ":" | cut -d: -f 2)		
	softIrqCount=$(echo $softIrqs | wc -w)
	
	first=$(echo $softIrqs|cut -d" " -f 1)	
	if [ $CPU_COUNT -lt $softIrqCount ]; then
		echo "Notice, CPU_COUNT:" $CPU_COUNT " is lt than nic softIrqCount :" $softIrqCount
	fi
	
	echo "$nic_dev nic softIrq list: " $softIrqs
	echo "total cpu list: " $cpuIds
	echo "first softIqr: " $first
	tmpC=0
	for s in $softIrqs 
	do
		tmpC=$(($tmpC + 1))
		if [ $(($tmpC+2)) -gt $CPU_COUNT ]; then
			#echo "Only can set "$CPU_COUNT" nic softIrqs,others will be ignored or be set manually!"
			#loop the cpu number setting
			#exit
			tmpC=$(($tmpC-2))
		fi
		echo "irq no. : "$s;
		local irq_t="/proc/irq/$s/smp_affinity_list"
		if [ -f $irq_t ]; then
			orig=$(cat );
			echo -n "	original set:" 
			echo $orig 
			cpuid=$tmpC
			if [ "$orig" == "$cpuid" ]; then
				echo -n "	already set to:"
				echo $cpuid
			else
				echo -n "	will modifie to: "
				echo $cpuid
				echo $cpuid > /proc/irq/$s/smp_affinity_list; 
				cid=$(cat "/proc/irq/$s/smp_affinity_list");
				if [ "$cpuid" == "$cid" ];then
					echo "	done"
				else
					echo "	Error setting,please check manually!!"
					echo "	check path:"/proc/irq/$s/smp_affinity_list
					exit
				fi
			fi
		fi
	done;
}


function usage(){
  echo "This script can set nic dev to spical cpu node"
	echo "     via modify /proc/irq/\$nic_irq_num/smp_affinity_list"
	echo 
	echo "USAGE:" $0 "-nic nic_dev"
	echo 
	echo 
	exit
}
 
############################MAIN################################

#if [ "$#" -lt 2 ]; then
#	usage
#	exit
#fi

#if [ "$1" == "-nic" ];then
#	nic_dev=$2
#else
#	usage
#fi

check_irqbalance_on
get_cpuinfo
echo $?
get_rpfs_affinity_mask


get_all_inused_interfaces
if [ $? -eq 0 ]; then
	echo $ALL_USED_INTERFACE
	for inf in $ALL_USED_INTERFACE; do
		check_smp_affinity_support $inf
	done
	echo '$SMP_AFFINITY_INF:'$SMP_AFFINITY_INF
	echo '$RPS_RFS_INF:'$RPS_RFS_INF
fi	
exit