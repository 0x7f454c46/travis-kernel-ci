#!/usr/bin/env python2

import dropbox, sys, os

prefix = "travis-kernel-ci"

d = os.getenv("TRAVIS_BUILD_ID")
if not d:
    d = "trash"

n = os.getenv("KNAME")
if not n:
    n = "undef"

access_token = os.getenv("DROPBOX_TOKEN")

client = dropbox.client.DropboxClient(access_token)

f = open(sys.argv[1])

fname = os.path.basename(sys.argv[1])
dname = sys.argv[2]

response = client.put_file(os.path.join(prefix, d, n, dname, fname), f)
print 'uploaded: ', response

#print "=====================", fname, "======================"
#print client.share(fname)['url']
#print "=====================", len(fname) * "=", "======================"

