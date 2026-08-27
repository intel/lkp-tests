#!/bin/sh

# Some misc-functions

. $LKP_SRC/lib/lkp_path.sh

setup_proxy()
{
	proxy_file=$(lkp_src)/etc/proxy
	[ -f "$proxy_file" ] && . "$proxy_file"
}
