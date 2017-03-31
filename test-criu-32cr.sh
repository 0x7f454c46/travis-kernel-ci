#!/bin/bash

echo "======================================"
echo "=== Start CRIU tests on linux-next ==="
echo "======================================"

PKGS="libaio-dev:i386 libcap-dev:i386"
NR_CPU=$(grep -c ^processor /proc/cpuinfo)

set -x -e

apt-get install -qq ${PKGS}

cd criu
make mrproper
git fetch origin

git checkout criu-dev
git clean -fdx
make -j$((NR_CPU+1)) COMPAT_TEST=y zdtm
ccache -s

./criu/criu check --extra --all || echo $?
./criu/criu check --feature compat_cr
./test/zdtm.py run -a -p 4 --keep-going
bash ./test/jenkins/criu-fault.sh
