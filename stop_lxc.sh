#!/bin/bash
set -x

if [ ${#@} -gt 0 ] && [ -d /var/lib/lxc/$1 ]; then 
	echo " stoping lxc container $1"
	lxc-stop -n $1
	umount /var/lib/lxc/$1/rootfs/var/cache/apt/
elif [  ${#@} -lt 1 ]; then
	TOTAL_CONTAINS=$(ls /var/lib/lxc/) 
	echo $TOTAL_CONTAINS
	for c in $TOTAL_CONTAINS; do
		if [ $c = 'test1' ]; then
			continue
		fi
		if [ -z $1 ]; then
			lxc-stop -n $c
		fi
		if [ -d /var/lib/lxc/$c ]; then
			echo "umount $c"
			umount /var/lib/lxc/$c/rootfs/var/cache/apt/
		fi
	done
fi

sleep 2
lxc-ls --fancy

