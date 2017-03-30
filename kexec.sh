#!/bin/bash

# Any failure here is fatal
set -x -e

CRIU_GIT="https://github.com/xemul/criu.git -b master"
HOME_PWD="$(pwd)"
PATCH_DIR="${HOME_PWD}/patches"
CRIU_BIN="${HOME_PWD}/${CRIU_DIR}/criu/criu"
CRIT_BIN="${HOME_PWD}/${CRIU_DIR}/crit/crit"
NR_CPU=$(grep -c ^processor /proc/cpuinfo)
NEW_KERNEL=""
PROCESS_TREE=""
SSHD_PID=
IMAGES_PATH=/imgs
RESTORE_SCRIPT="$(pwd)/kexec-restore.sh"
PKGS="protobuf-c-compiler libprotobuf-c0-dev libaio-dev libprotobuf-dev
	protobuf-compiler python-ipaddr libcap-dev libnl-3-dev gcc-multilib
	libc6-dev-i386 gdb bash python-protobuf libnet-dev util-linux asciidoc
	kexec-tools libssl-dev libelf-dev strace ccache"
export CC="ccache gcc"
export CXX="ccache g++"
export CCACHE_DIR="/home/travis/.ccache"
export PATH="/usr/lib/ccache:$PATH"

### Preparations

function install_pkgs()
{
	apt-get update -qq
	apt-get install -qq ${PKGS}
	pip install dropbox
}

function prepare_criu()
{
	echo "Cloning CRIU..."
	git clone --depth 1 ${CRIU_GIT} "${CRIU_DIR}"

	cd "${CRIU_DIR}"
	echo "Applying CRIU patches..."
	git am ${PATCH_DIR}/criu/*

	echo "Building CRIU..."
	time make -j$((NR_CPU+1))
	echo "Prepared $(git describe) CRIU."
	ccache -s
	cd -
	make pidns
	echo "Checking CRIU:"
	${CRIU_BIN} check --extra --all || true # fails, but it's OK
}

function prepare_kernel()
{
	echo "Cloning kernel..."
	git clone --depth 1 ${KGIT} "${KPATH}"

	echo "Building kernel..."
	cp "${KCONFIG}" "${KPATH}/.config"
	cd "${KPATH}"
	make olddefconfig
	# get rid of modules in config
	yes "" | make localyesconfig
	time make -j$((NR_CPU+1))
	NEW_KERNEL="$(make -s --no-print-directory kernelrelease)"
	echo "Prepared ${NEW_KERNEL} kernel."
	ccache -s
	cd -
	if [[ ${DEBUG} == "y" ]] ; then
		pwd
		ls -l
		ls -l ${KPATH}/arch/x86/boot/bzImage
	fi
}

#
# init (pid = 1)
# \_ /usr/sbin/sshd -D (our process tree)
#   \_ sshd: travis [priv] (sshd daemon with some fifo)
#     \_ ...
#     \_ ...
function find_process_tree_for_cr()
{
	PROCESS_TREE=$$
	SSHD_PID=$$
	local pid=$$

	while [[ $pid -ne 1 ]] ; do
		SSHD_PID=${PROCESS_TREE}
		PROCESS_TREE=${pid}
		pid=$(awk '{ if ($1=="PPid:") print $2 }' \
			/proc/${PROCESS_TREE}/status)
	done
	PROCESS_TREE=${pid}
}

function prepare_env()
{
	mkdir -p "${LOGS}"
	rm -rf ${LOGS}/*
	mkdir -p ${IMAGES_PATH}
	rm -rf ${IMAGES_PATH}/*

	find_process_tree_for_cr
	local SYSTEMD_FIFO="$(lsof -p ${SSHD_PID} |			\
		grep /run/systemd/sessions | awk '{ print $9 }')"
	echo "Systemd fifo file ${SYSTEMD_FIFO}"
	modprobe tun
	modprobe macvlan
	modprobe veth
	# Disable Docker daemon start after reboot; upstart way
	echo manual > /etc/init/docker.override

	if [[ -f /etc/init/criu.conf ]] ; then
		unlink /etc/init/criu.conf
	fi
	cat > /etc/init/criu.conf <<-EOF
		start on runlevel [2345]
		stop on runlevel [016]
		exec ${RESTORE_SCRIPT} $(pwd) ${SYSTEMD_FIFO}
	EOF

	if [[ ${DEBUG} == "y" ]] ; then
		cat /etc/init/criu.conf
	fi

	cat > /etc/network/if-pre-up.d/iptablesload <<-EOF
		#!/bin/sh
		iptables-restore < /etc/iptables.rules
		unlink /etc/network/if-pre-up.d/iptablesload
		unlink /etc/iptables.rules
		exit 0
	EOF

	chmod +x /etc/network/if-pre-up.d/iptablesload
	iptables-save -c > /etc/iptables.rules

	echo $TRAVIS_BUILD_ID > /travis_id
	set +x
	echo $DROPBOX_TOKEN > /dropbox
	set -x
}

function debug_preparations()
{
	set -x
	cat /proc/cpuinfo
	echo "NR_CPU = ${NR_CPU}"
	uname -a
	lsmod
	ip a
	ip r
	iptables -L
	cat /proc/cmdline
	cat /proc/self/mountinfo
	ps axf
	set +x
	echo "Process tree to CR:"
	ps -fH --ppid ${PROCESS_TREE}
}

install_pkgs
prepare_criu
prepare_kernel
prepare_env
debug_preparations 2>&1 > "${LOGS}/prepare.log"

### Kexec

export CRIU_BIN IMAGES_PATH PROCESS_TREE CRIT_BIN

sudo setsid bash -c "sudo setsid ./kexec-dump.sh &"

for i in `seq 10`; do
	echo "Waiting for kexec... kernel is $(uname -a)"
	sleep 15
	if [[ -f /rebooted ]]; then
		if [[ "${NEW_KERNEL}" == "$(uname -r)" ]] ; then
			exec bash -c ${TEST_CMD}
		else
			echo "Rebooted, but failed to check kernel $(uname -a)"
			exit 1
		fi
	fi
	if [[ -f /reboot.failed ]] ; then
		echo "Kexec failed"
		exit 1
	fi
done

echo "Kexec timeouted"
exit 1
