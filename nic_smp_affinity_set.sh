#!/bin/bash
# Author:"Wang Chunsheng"<chunshengster@gmail.com>
# Date: 2013.05.09
# usage example : ./$0 -a -o/-q
# 
# Some documents can help you to understand smp_affinity or rps/rfs, 
#		please visit: http://blog.chunshengster.me/2013/05/smp_irq_affinity.html
# TODO:add numa node support 


#set -x

#for grep nic card pattern, you can change this one to meet your system environment!
NIC_PATTERN='em\|eth\|p1'
RX_PATTERN='rx-'

LS='/bin/ls'
CAT='/bin/cat'
GREP='/bin/grep'
PS='/bin/ps'
WC='/usr/bin/wc'

#TODO:add support to ubuntu system stop a service
#this time only support Redhat system 
SERVICE='/sbin/service'
CHKCONFIG='/sbin/chkconfig'

DISABLE_IRQBALANCE='NO'
ONLY_SHOW='NO'
QUIET='NO'
LOG_MSG='NO'

SYSNET_PATH='/sys/class/net'
QUEUE_PATH='queues'
RPS_ENTRIES_FILE="/proc/sys/net/core/rps_sock_flow_entries"
RPS_ENTRIES_NUM=32768
RPS_FLOW_CNT=4096

CPU_IDS=''
CPU_COUNT=0
ALL_USED_INTERFACE=''
SMP_AFFINITY_INF=''
RPS_RFS_INF=''
RPS_RFS_MASK=''


function parser_args() {
	local all_run=0
	while test -n "$1"; do
		case "$1" in
		-o|--only_show)
			DISABLE_IRQBALANCE='NO'
			ONLY_SHOW='YES'
			shift
			;;
		-q|--quiet)
			QUIET='YES'
			shift
			;;
		-a|--all)
			all_run=1
			shift
			;;
		-b|--both)
			both=1
			shift
			;;
		-d|--disable_irqbalance)
			DISABLE_IRQBALANCE='YES'
			shift
			;;
		-n|--nic)
			ALL_USED_INTERFACE=$2
			shift 2
			;;
		-h|--help)
			usage
			return 1
			;;
		*)
			echo "Unknown argument: $1"
			usage
			return 1
			;;
		esac
	done
	
	if [ $all_run -eq 0 ] && [ -z $ALL_USED_INTERFACE ]; then
		usage
		return 1
	fi	
	
	###
	# suck !!!!
	if [ "$ONLY_SHOW" == 'YES' ] && [ "$QUIET" == 'YES' ]; then
		echo '$ONLY_SHOW:'$ONLY_SHOW
		echo '$QUIET:'$QUIET
		echo "[ERROR] You can set either -o or -q, but can not both !"
		return 1
	else
		return 0
	fi
	
	return 1
}

function debug_echo() {
	[ "$QUIET" == 'NO' ] && echo "$*"
	[ "$LOG_MSG" == 'YES' ] && logger "$*"
}

function check_interface_inuse() {
	if [ ${#@} -lt 1 ]; then
		return 1
	fi
	if [ -f "$SYSNET_PATH/$1/operstate" ]; then 
		local updown=$($CAT "$SYSNET_PATH/$1/operstate")
		if [ $? -eq 0 ]; then
			if [ "$updown" == "up" ];then
				return 0
			else
				return 1
			#return  "$updown" == "up"  ? 0 : 1
			fi
		fi
	fi
	return 1
}

function get_all_inused_interfaces() {
	local allInterFaces=$($LS "$SYSNET_PATH" | $GREP $NIC_PATTERN)
	#local len_t=${#allInterFaces}
	local len_t=$(echo $allInterFaces | $WC -w)
	if [ $len_t -lt 1 ];then
		return 1
	fi
	
	for inf_t in $allInterFaces; do
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

# get all nic card that support smp_affinity or rfs/rfs ,if no one ,return error
function get_smp_affinity_nics() {
	if [ -z $1 ];then
		return 1
	fi
	local nic_t_queue_count=$($LS "$SYSNET_PATH/$1/$QUEUE_PATH" | $GREP -c $RX_PATTERN)
	if [ $nic_t_queue_count -gt 1 ]; then
		SMP_AFFINITY_INF=$SMP_AFFINITY_INF" "$1
	else
		RPS_RFS_INF=$RPS_RFS_INF" "$1
	fi
	local count_t=$(echo $SMP_AFFINITY_INF$RPS_RFS_INF|$WC -w)
	
	if [ $count_t -gt 0 ]; then
		return 0
	fi
	return 1
}


# check for irq_balance running
# if $DISABLE_IRQBALANCE == 'YES' then disable irqbalance service
function check_irqbalance_on() {
	IRQBALANCE_ON=$($PS ax | $GREP -v "grep" | $GREP -q "irqbalance"; echo $?)

	if [ "$IRQBALANCE_ON" == "0" ] ; then
		echo " WARNING: irq_balance is running and will"
		echo "          likely override this script's affinitization."
		echo "          Please stop the irq_balance service and/or execute"
		echo "          'killall irqbalance'" 
		if [ "$ONLY_SHOW" == 'YES' ];then
			return 0
		fi
		if [ "$DISABLE_IRQBALANCE" == 'YES' ]; then
			$SERVICE irqbalance stop
			if [ $? -eq 0 ]; then 
			return 0
			fi
		fi
	else
		return 0
	fi
	return 1
}

function get_cpuinfo() {
	CPU_IDS=$($CAT "/proc/cpuinfo" | $GREP processor | $GREP -v grep | cut -d: -f 2)	
	CPU_COUNT=$(echo $CPU_IDS | $WC -w)
	if [ $CPU_COUNT -lt 1 ];then
		return 1
	fi
	return 0
}

#
function get_rpfs_affinity_mask() {
	local t=$(($CPU_COUNT/4))
	if [ $t -lt 1 ]; then
		return 1
	fi
	
	for i in $(seq $t); do
		RPS_RFS_MASK=$RPS_RFS_MASK'f'
	done
	#local t1=$(($CPU_COUNT-$t))
	#if [ $t1 -gt 0 ]; then
	#	for i in $(seq $t1); do
	#		RPS_RFS_MASK="0"$RPS_RFS_MASK
	#	done
	#fi
	
	local ok_t=$(echo $RPS_RFS_MASK | $GREP -q 'f'; echo $?)
	return $ok_t				
}

function do_rpfs_enable() {
	nic_dev=$1
	
	debug_echo "dealing with interface :"$nic_dev

	local rps_cpus_file_t="$SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_cpus"
	debug_echo "dealing with rps_cpus_file :"$rps_cpus_file_t
	if [ -f $rps_cpus_file_t ]; then
		local rps_cpus=$($CAT $rps_cpus_file_t | tr -d '0')
		if [ -z "$rps_cpus" ]; then
			local rps_cpus=$($CAT $rps_cpus_file_t)
		fi
		#compare current rps_cus to $RPS_RFS_MASK
		if [ "$rps_cpus" != "$RPS_RFS_MASK" ]; then
			if [ "$ONLY_SHOW" == 'NO' ]; then
				echo $RPS_RFS_MASK > $rps_cpus_file_t
				local rps_cpus_tt=$($CAT $rps_cpus_file_t | tr -d '0')
				if [ "$rps_cpus_tt" != "$RPS_RFS_MASK" ]; then
					echo "	[ERROR]:setting $rps_cpus_file_t to $RPS_RFS_MASK error !"
					return 1
				fi
			fi
			debug_echo "	origin value :"$rps_cpus
			debug_echo "		will be set to :"$RPS_RFS_MASK
		else
			debug_echo "	already been set to:"$RPS_RFS_MASK
		fi
	else
		return 1
	fi
	
	local rps_flow_cnt_file_t="$SYSNET_PATH/$nic_dev/$QUEUE_PATH/rx-0/rps_flow_cnt"
	debug_echo "dealing with rps_flow_cnt_file :"$rps_flow_cnt_file_t
	if [ -f $rps_flow_cnt_file_t ]; then
		local rps_flow_cnt=$($CAT $rps_flow_cnt_file_t)
		#compare current rps_flow_cnt to $RPS_FLOW_CNT
		if [ "$rps_flow_cnt" != "$RPS_FLOW_CNT" ];then
			#	echo $RPS_FLOW_CNT 
			if [ "$ONLY_SHOW" == 'NO' ];then 
				echo $RPS_FLOW_CNT > $rps_flow_cnt_file_t
				local rps_flow_cnt_tt=$($CAT $rps_flow_cnt_file_t)
				if [ $rps_flow_cnt_tt != $RPS_FLOW_CNT ]; then
					echo "	[ERROR]:setting $rps_flow_cnt_file_t to $RPS_FLOW_CNT error !"
					return 1
				fi
			fi
			debug_echo "	origin value :" $rps_flow_cnt
			debug_echo "		will be set to :"$RPS_FLOW_CNT
		else
			debug_echo "		already been set to:"$RPS_FLOW_CNT
		fi
	else
		return 1
	fi
	return 0	
}

function do_rps_entries_enable() {
	debug_echo "dealing with rps_entries :"$RPS_ENTRIES_FILE
	local rps_entries=$($CAT $RPS_ENTRIES_FILE)
	if [ $rps_entries -eq $RPS_ENTRIES_NUM ]; then
		return 0
	else
		if [ "$ONLY_SHOW" == 'NO' ];then
			echo $RPS_ENTRIES_NUM > $RPS_ENTRIES_FILE
			local rps_entries_t=$($CAT $RPS_ENTRIES_FILE)
			if [ $rps_entries -eq $RPS_ENTRIES_NUM ]; then
				return 0
			else
				echo "	[ERROR]:setting $RPS_ENTRIES_FILE to $RPS_ENTRIES_NUM error !"
				return 1
			fi
		else
			debug_echo "	origin value :"$rps_entries
			debug_echo "	will be set to :"$RPS_ENTRIES_NUM
		fi
	fi
}

function do_smpaffinity_enable() {
	nic_dev=$1
	softIrqs=$($CAT "/proc/interrupts" | $GREP $nic_dev"-" | tr -s " " ":" | cut -d: -f 2)		
	softIrqCount=$(echo $softIrqs | $WC -w)
	
	#first=$(echo $softIrqs|cut -d" " -f 1)	
	if [ $CPU_COUNT -lt $softIrqCount ]; then
		debug_echo "Notice, CPU_COUNT:" $CPU_COUNT " is little than nic softIrqCount :" $softIrqCount
	fi
	
	debug_echo "$nic_dev nic softIrq list: "$softIrqs
	debug_echo "Total cpu list: "$CPU_IDS
	#debug_echo "First softIqr: "$first
	
	tmpC=$CPU_COUNT
	
	for s in $softIrqs; do
		tmpC=$(($tmpC - 1))
		if [ $tmpC -lt 0 ]; then
			tmpC=$(($CPU_COUNT-1))
		fi
		
		debug_echo "irq no. : "$s;
		local irq_t="/proc/irq/$s/smp_affinity_list"
		if [ -f $irq_t ]; then
			orig=$(cat $irq_t);
			debug_echo "	original set :"$orig 
			cpuid=$tmpC
			if [ "$orig" == "$cpuid" ]; then
				debug_echo "	already set to :"$cpuid
			else
				debug_echo "	will modified to: "$cpuid
				if [ "$ONLY_SHOW" == 'NO' ]; then
					echo $cpuid > $irq_t;
					cid=$(cat "$irq_t");
					if [ "$cpuid" == "$cid" ];then
						debug_echo "	done"
					else
						debug_echo "	Error setting,please check manually!!"
						debug_echo "	check path:$irq_t"
						return 1
					fi
				fi
			fi
		fi
	done
	return 0
}

function usage() {
	echo "This Script will set smp_affinity or rps/rps automatically"
	echo "	via modify '/sys/class/net/' files and/or '/proc/' sysfs"
	echo "USAGE:$0 -a -o/-q"
	echo "	-a/--all:	Check all in_used interfaces"
	echo "	-b/--both:	Both set rps/rqs and smp irq affinity"
	echo "	-n/--nic:	Only check/set the specified nic interface"
	echo "	-d/--disable_irqbalance:	Disable irq_balance service automatically"
	echo "	-o/--only_show:	Only show what will happen"
	echo "	-q/--quiet:	Nothing will display if no error happen" 
	exit 1
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

#echo "$*"
if [ ${#@} -lt 1 ]; then
	usage
fi

parser_args $*
if [ $? -gt 0 ]; then
	exit
fi


check_irqbalance_on
if [ $? -gt 0 ]; then
	exit
fi

if [ $(echo $ALL_USED_INTERFACE | $WC -w) -lt 1 ]; then
	get_all_inused_interfaces
	if [ $? -gt 0 ]; then
		exit
	fi
fi

get_cpuinfo
if [ $? -gt 0 ]; then
	exit
fi

debug_echo "All used interface :" $ALL_USED_INTERFACE
for inf in $ALL_USED_INTERFACE; do
	get_smp_affinity_nics $inf
done

debug_echo '	$SMP_AFFINITY_INF:'$SMP_AFFINITY_INF
debug_echo '	$RPS_RFS_INF:'$RPS_RFS_INF

if [ $(echo $SMP_AFFINITY_INF | $WC -w) -gt 0 ]; then
	for inf_t in $SMP_AFFINITY_INF; do
		do_smpaffinity_enable $inf_t
		if [ $? -gt 0 ]; then
			exit 1
		fi
	done
fi

if [ $(echo $RPS_RFS_INF | $WC -w) -gt 0 ]; then
	get_rpfs_affinity_mask
	if [ $? -gt 0 ]; then
		exit 1
	else
		do_rps_entries_enable
		for inf_t in $RPS_RFS_INF; do
			do_rpfs_enable $inf_t
			if [ $? -gt 0 ]; then
				exit 1
			fi
		done
	fi
fi
	
	
exit 1
