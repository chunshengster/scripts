#!/bin/bash
#
# chunshengster@gmail.com
# for mounting ubuntu auto mount apt repo sharing with lxc containers
TOTAL_CONTAINS=$(ls /var/lib/lxc/)
echo $TOTAL_CONTAINS
for c in $TOTAL_CONTAINS; do
	if [ -d /var/lib/lxc/$c ]; then
		echo $c
		mount --bind /var/cache/apt /var/lib/lxc/$c/rootfs/var/cache/apt
	fi
done
