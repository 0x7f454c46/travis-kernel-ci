#!/bin/bash

set -x -e

function criu_dump()
{
	${CRIU_BIN} dump -D "${IMAGES_PATH}" -o "${LOGS}/dump.log"	\
		-t ${PROCESS_TREE} -j --tcp-established --ext-unix-sk	\
		-vvvv -l --ghost-limit 10485760

	if [[ ${DEBUG} == "y" ]] ; then
		ls -l "${IMAGES_PATH}"
	fi

	${CRIT_BIN} show ${IMAGES_PATH}/tty-info.img |			\
		sed 's/"index": \([0-9]*\)/"index": 1\1/' |		\
		${CRIT_BIN} encode > ${IMAGES_PATH}/tty-info.img.new
	mv ${IMAGES_PATH}/tty-info.img.new ${IMAGES_PATH}/tty-info.img
	${CRIT_BIN} show ${IMAGES_PATH}/reg-files.img |			\
		sed 's|/dev/pts/\([0-9]*\)|/dev/pts/1\1|' |		\
		${CRIT_BIN} encode > ${IMAGES_PATH}/reg-files.img.new
	mv ${IMAGES_PATH}/reg-files.img.new ${IMAGES_PATH}/reg-files.img
	${CRIT_BIN} show ${IMAGES_PATH}/tty-info.img > "${LOGS}/tty-info"
}

function kexec_load()
{
	if [[ ${DEBUG} == "y" ]] ; then
		pwd
		ls -l
		ls -l ${KPATH}/arch/x86/boot/bzImage
	fi
	kexec -l ${KPATH}/arch/x86/boot/bzImage --command-line "${CMDLINE}"
}

function perform_kexec()
{
	{
		criu_dump
		if [[ ${DEBUG_NO_KEXEC} == "y" ]] ; then
			$(grep exec /etc/init/criu.conf)
		fi
		kexec_load
		kexec -e
	} || touch /reboot.failed
}

perform_kexec
