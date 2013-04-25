#!/bin/bash
# Author:"Wang Chunsheng"<chunshengster@gmail.com
# Date: xxxx.xx.xx
# USAGE: ./$0 -nic em1

function usage(){
  echo "This script can set nic dev to spical cpu node"
	echo "     via modify /proc/irq/\$nic_irq_num/smp_affinity_list"
	echo 
	echo "USAGE:" $0 "-nic nic_dev"
	echo 
	echo 
	exit
}
 

if [ "$#" -lt 2 ]; then
	usage
	exit
fi

if [ "$1" == "-nic" ];then
	nic_dev=$2
else
	usage
fi

# check for irqbalance running
IRQBALANCE_ON=`ps ax | grep -v grep | grep -q irqbalance; echo $?`
if [ "$IRQBALANCE_ON" == "0" ] ; then
        echo " WARNING: irqbalance is running and will"
        echo "          likely override this script's affinitization."
        echo "          Please stop the irqbalance service and/or execute"
        echo "          'killall irqbalance'"
	exit;
fi

softIrqs=$(cat /proc/interrupts | grep $nic_dev | tr -s " " ":" |cut -d: -f 2)		
softIrqCount=$(echo $softIrqs | wc -w)
cpuIds=$(cat /proc/cpuinfo | grep processor | cut -d: -f 2)	
cpuCount=$(echo $cpuIds | wc -w)
first=$(echo $softIrqs|cut -d" " -f 1)	
if [ $cpuCount -lt $softIrqCount ]; then
	echo "Notice, cpuCount:" $cpuCount " is lt than nic softIrqCount :" $softIrqCount
fi

echo "$nic_dev nic softIrq list: " $softIrqs
echo "total cpu list: " $cpuIds
echo "first softIqr: " $first
tmpC=0
for s in $softIrqs 
do
	tmpC=$(expr $tmpC + 1)
	if [ $tmpC -gt $cpuCount ]; then
		echo "Only can set "$cpuCount" nic softIrqs,others will be ignored or be set manually!"
		#TODO:loop the cpu number setting
		exit
	fi
	echo "irq no. : "$s;
	orig=$(cat /proc/irq/$s/smp_affinity_list);
	echo -n "	original set:" 
	echo $orig 
	cpuid=$(expr $s - $first)
	if [ "$orig" == "$cpuid" ]; then
		echo -n "	already set to:"
		echo $cpuid
	else
		echo -n "	will modifie to: "
		echo $cpuid
		echo $cpuid > /proc/irq/$s/smp_affinity_list; 
		cid=$(cat /proc/irq/$s/smp_affinity_list);
		if [ "$cpuid" == "$cid" ];then
			echo "	done"
		else
			echo "	Error setting,please check manually!!"
			echo "	check path:"/proc/irq/$s/smp_affinity_list
			exit
		fi
	fi
done;
