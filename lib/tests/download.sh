#!/bin/bash

# Public download utility for LKP tests.
# Supports simple wget and mirror fallback.

download_from_url()
{
	local url="$1"
	local file="$2"

	# A pre-created destination directory means $url is a directory
	# source: wget -O cannot write to a directory (fails "Is a
	# directory"), so mirror it recursively instead, same technique
	# lib/wget.sh's http_get_directory uses for initrd/ucode directories.
	if [[ -d "$file" ]]; then
		echo "Downloading directory from: $url"
		wget -q -r -np -nd -P "$file" "${url%/}/"
		return
	fi

	local filename
	filename=$(basename "$file")
	[[ -n "$filename" ]] || return

	local download_cmd="wget -q -O"

	# Try customized mirror first if configured
	if [[ -n "$LKP_MIRROR" ]]; then
		local mirror_url="${LKP_MIRROR}/${filename}"
		echo "Attempting download from LKP mirror: $mirror_url"

		if $download_cmd "$file" "$mirror_url"; then
			echo "Download from mirror successful."
			return 0
		else
			echo "Download from mirror failed. Falling back to original URL."
			rm -f "$file" # Clean up potential partial download
		fi
	fi

	# Fallback to original URL
	echo "Downloading from: $url"
	$download_cmd "$file" "$url"
}

lkp_download()
{
	download_from_url "$@"
}
