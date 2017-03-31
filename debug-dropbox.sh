#!/bin/bash

for i in ${LOGS}/*
do
	./dropbox_upload.py $i
	rm $i
done

exit 0
