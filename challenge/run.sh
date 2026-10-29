#!/bin/sh
chmod 400 /flag.txt
exec socat -d tcp-listen:1338,fork,reuseaddr exec:'/app/turbo-malloc',su=nobody,stderr
