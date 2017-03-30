#!/bin/bash

for i in ${LOGS}/*
do
	./dropbox_upload.py $i
done

exit 0
