#!/bin/sh

. $LKP_SRC/lib/debug.sh
. $LKP_SRC/lib/env.sh

fixup_java_home()
{
	if [ -d /usr/lib/jvm/java-1.11.0-openjdk ]; then
		export JAVA_HOME=/usr/lib/jvm/java-1.11.0-openjdk
		export CASSANDRA_USE_JDK11=true
	elif [ -d /usr/lib/jvm/java-11-openjdk-amd64 ]; then
		export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
		export CASSANDRA_USE_JDK11=true
	else
		local dir
		for dir in "/usr/lib/jvm/java-"*-openjdk*; do
			[ -d "$dir" ] || continue

			export JAVA_HOME=$dir
			break
		done
	fi

	[ -n "$JAVA_HOME" ] || die "NO available JAVA_HOME"

	echo "JAVA_HOME=$JAVA_HOME"
}

# mainly to resolve "/usr/bin/env: ‘python’: No such file or directory"
fixup_python()
{
	has_cmd python && return

	if has_cmd python2; then
		ln -sf $(cmd_path python2) /usr/bin/python
	elif has_cmd python3; then
		ln -sf $(cmd_path python3) /usr/bin/python
	else
		die "No python found"
	fi

	echo "python: $(ls -l /usr/bin/python)"
}
