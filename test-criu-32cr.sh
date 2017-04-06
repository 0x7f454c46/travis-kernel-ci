#!/bin/bash

echo "======================================"
echo "=== Start CRIU tests on linux-next ==="
echo "======================================"

PKGS="libcap-dev:i386 libaio1:i386 libaio-dev:i386 libnl-3-dev:i386	\
	libnl-route-3-dev:i386"
NR_CPU=$(grep -c ^processor /proc/cpuinfo)
FAILED=0
HOME="$(pwd)"

function dropbox_dump_upload()
{
	if [[ $FAILED -eq 1 ]] ; then
		find ./test/dump -type f | while read f ; do
			${HOME}/dropbox_upload.py "$f" "$(dirname $f)"
		done
	fi
}

set -x -e

# Building criu-dev's CRIU binary
cd criu
make mrproper
git fetch origin

git checkout criu-dev
git clean -fdx
make -j$((NR_CPU+1))
ccache -s

# Installing 32-bit libraries, it needs to be done after
# building CRIU as *-dev versions in ubuntu conflicts
# for :x86_64 and for :i386.
dpkg --add-architecture i386
apt-get update -qq
apt-get install -qq ${PKGS}

make -j$((NR_CPU+1)) COMPAT_TEST=y -C test/zdtm
ccache -s

umask 0000

chmod 0777 test/
chmod 0777 test/zdtm/static
chmod 0777 test/zdtm/transition

./criu/criu check --extra --all || echo $?
./criu/criu check --feature compat_cr
./test/zdtm.py run -a -p 4 -x zdtm/static/autofs --keep-going || FAILED=1
echo 'function prep() { :; }' > ./test/jenkins/criu-lib.sh
bash ./test/jenkins/criu-fault.sh || FAILED=1
dropbox_dump_upload

exit $FAILED
