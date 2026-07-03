#!/bin/bash

log()
{
	echo "$(date +'%F %T') INFO -- $*"
}

log_info()
{
	echo "$(date +'%F %T') INFO -- $*"
}

log_debug()
{
	echo "$(date +'%F %T') DEBUG -- $*"
}

log_warn()
{
	echo "$(date +'%F %T') WARN -- $*" >&2
}

log_error()
{
	echo "$(date +'%F %T') ERROR -- $*" >&2
}
