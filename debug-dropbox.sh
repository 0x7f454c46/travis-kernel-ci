#!/bin/bash

for i in ${LOGS}/*
do
	./dropbox_upload.py $i "logs"
	rm $i
done

exit 0
