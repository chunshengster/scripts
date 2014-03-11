#!/bin/bash
set -x
if [ ${#@} -gt 0 ] && [ -d /var/lib/lxc/$1 ]; then 
	echo " starting lxc container $1"
	mount -o bind /var/cache/apt/	/var/lib/lxc/$1/rootfs/var/cache/apt/
	lxc-start -d -n $1
elif [  ${#@} -lt 1 ]; then
	TOTAL_CONTAINS=$(ls /var/lib/lxc/) 
	echo $TOTAL_CONTAINS
	for c in $TOTAL_CONTAINS; do
		if [ $c = 'test1' ]; then
			continue
		fi
		if [ -d /var/lib/lxc/$c ]; then
			echo $c
			mount -o bind /var/cache/apt/ /var/lib/lxc/$c/rootfs/var/cache/apt/
		fi
		if [ -z $1 ]; then
			lxc-start -d -n $c
		fi
	done
fi

sleep 3
lxc-ls --fancy

