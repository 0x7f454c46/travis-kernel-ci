#!/bin/bash

for i in ${LOGS}/* ; do
	echo "===== $i ====="
	cat $i
done
