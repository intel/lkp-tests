#!/bin/bash

create_lkp_user() {
	grep -q ^lkp: /etc/passwd && return

	echo -n "Do you agree to create lkp users for testing? [Y/n] "
	read -r input
	case $input in
		N|n)
			echo "error: lkp user is required to run lkp tests"
			exit 1
		;;
		*)
			if useradd -m -s /bin/bash lkp; then
				echo "Create lkp user successfully."
			else
				echo "Create lkp user failed."
				exit 1
			fi
		;;
	esac
}
