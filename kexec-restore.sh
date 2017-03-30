#!/bin/bash
# $1 - pwd to restore
# $2 - some systemd fifo to create

set -x

IMAGES_PATH=/imgs
CRIU_BIN="${1}/${CRIU_DIR}/criu/criu"

function restore_env()
{
	TRAVIS_BUILD_ID=`cat /travis_id`
	export TRAVIS_BUILD_ID
	DROPBOX_TOKEN=`cat /dropbox`
	export TRAVIS_BUILD_ID
	cd "$1"

	mkfifo "$2"
	chmod 0600 "$2"
}

function restore_debug()
{
	uname -a
	lsmod
	ps axf
	ip a
	ip r
	iptables -L
}

sleep 15
restore_env
restore_debug > "${LOGS}/pre-restore"

dmesg -c > "${LOGS}/dmesg.log"

./debug-dropbox.sh

./pidns ${CRIU_BIN} restore -D ${IMAGES_PATH} 				\
	-o "${LOGS}/restore.log" -j --tcp-established --ext-unix-sk	\
	-vvvv -l &
CRIU_PID=$!

sleep 10

dmesg >> "${LOGS}/dmesg.log"

if [[ "`cat /proc/sys/kernel/tainted`" -ne "0" ]] ; then
	echo "Kernel is tainted"
fi

touch /rebooted

./debug-dropbox.sh

wait -n $CRIU_PID

if [[ "${DEBUG}" == "y" ]] ; then
	./dump_logs.sh
fi
