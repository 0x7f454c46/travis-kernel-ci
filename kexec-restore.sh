#!/bin/bash
# $1 - pwd to restore
# $2 - some systemd fifo to create
# $3 - logs path
# $4 - criu dir
# $5 - debug (y/n)

set -x

IMAGES_PATH=/imgs
HOME_PWD="$1"
FIFO="$2"
export LOGS="$3"
CRIU_DIR="$4"
DEBUG="$5"

exec &>> "${LOGS}/travis-restore.log"

CRIU_BIN="${HOME_PWD}/${CRIU_DIR}/criu/criu"

function restore_env()
{
	TRAVIS_BUILD_ID=`cat /travis_id`
	KNAME=`cat /kname`
	export TRAVIS_BUILD_ID KNAME

	set +x
	DROPBOX_TOKEN=`cat /dropbox`
	export DROPBOX_TOKEN
	set -x

	cd "$HOME_PWD"

	mkfifo "$FIFO"
	chmod 0600 "$FIFO"
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
restore_debug > "${LOGS}/pre-restore.log"

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
