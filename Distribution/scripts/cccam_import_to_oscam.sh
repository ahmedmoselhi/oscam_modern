#!/bin/sh
#
# Import free CCcam/Newcamd lines from public pages, convert them to OSCam readers
# and write/update oscam.server in common STB paths.
#
# Usage:
#   sh cccam_import_to_oscam.sh [output_server_file]
#
# Notes:
# - This script is designed to be callable from OSCam WebIf "Script" page when
#   `httpscript` points to its directory.
# - Default output path is /tmp/server; the script then copies content to
#   several known oscam.server locations.

set -u

WORKDIR="/tmp/xtest"
CCCAM_CFG="/tmp/CCcam.cfg"
CCCAM_CFG_FILTERED="/tmp/CCcam.cfg2"
SOURCE_PAGE="$WORKDIR/CCcam"
TARGET_SERVER="${1:-/tmp/server}"
OUTPUT_SERVER="/tmp/server.generated"
OUTPUT_NEWCAMD="/tmp/server_n"
AUTOGEN_BEGIN="# ---- OSCAM AUTO-GENERATED READERS (cccam_import_to_oscam.sh) BEGIN ----"
AUTOGEN_END="# ---- OSCAM AUTO-GENERATED READERS (cccam_import_to_oscam.sh) END ----"

mkdir -p "$WORKDIR" || exit 1

cleanup() {
	rm -f "$OUTPUT_NEWCAMD" "$OUTPUT_SERVER" "$CCCAM_CFG_FILTERED" "$SOURCE_PAGE" "$WORKDIR"/soubor* "$WORKDIR"/testious_*.tmp "$WORKDIR"/testious_page.html
	rmdir "$WORKDIR" 2>/dev/null || true
}

ensure_curl() {
	if command -v curl >/dev/null 2>&1; then
		return 0
	fi

	if command -v opkg >/dev/null 2>&1; then
		opkg update && opkg install curl
	elif command -v apt-get >/dev/null 2>&1; then
		apt-get update && apt-get install -y curl
	fi

	command -v curl >/dev/null 2>&1
}

fetch_cccam_lines() {
	url="$1"
	pattern="$2"
	outfile="$3"
	curl --max-time 12 --limit-rate 100K -s -k -L "$url" > "$SOURCE_PAGE" || true
	grep -o -i -E "$pattern" "$SOURCE_PAGE" > "$outfile" || true
}

append_testious() {
	current_date="$(date +%Y-%m-%d)"
	testious_url="https://testious.com/old-free-cccam-servers/${current_date}/"

	echo "Downloading from testious.com date ${current_date}..."
	curl --max-time 12 --limit-rate 100K -Lk -s -A "Mozilla/5.0" "$testious_url" > "$WORKDIR/testious_page.html" || true

	if [ ! -s "$WORKDIR/testious_page.html" ]; then
		echo "No page downloaded from testious.com"
		return 0
	fi

	cat "$WORKDIR/testious_page.html" | grep -o '<div style="background-color: #EEEEEE[^>]*>.*</div>' |
		sed 's/<div[^>]*>//g; s#</div>##g; s#<br>#\n#g; s/^[[:space:]]*//' |
		grep '^C:' > "$WORKDIR/testious_cccam.tmp" || true

	cat "$WORKDIR/testious_page.html" | grep -o '<div style="background-color: #EEEEEE[^>]*>.*</div>' |
		sed 's/<div[^>]*>//g; s#</div>##g; s#<br>#\n#g; s/^[[:space:]]*//' |
		grep '^N:' > "$WORKDIR/testious_newcamd.tmp" || true

	if [ ! -s "$WORKDIR/testious_cccam.tmp" ]; then
		tr '><' '\n\n' < "$WORKDIR/testious_page.html" | grep '^C:' | sed 's/^[[:space:]]*//' > "$WORKDIR/testious_cccam.tmp" || true
	fi
	if [ ! -s "$WORKDIR/testious_newcamd.tmp" ]; then
		tr '><' '\n\n' < "$WORKDIR/testious_page.html" | grep '^N:' | sed 's/^[[:space:]]*//' > "$WORKDIR/testious_newcamd.tmp" || true
	fi

	cat "$WORKDIR/testious_cccam.tmp" >> "$CCCAM_CFG" 2>/dev/null || true
	cat "$WORKDIR/testious_newcamd.tmp" >> "$CCCAM_CFG" 2>/dev/null || true
}

build_cccam_cfg() {
	: > "$CCCAM_CFG"

	fetch_cccam_lines "https://cccamsate.com/free" 'C: [a-z][^<]*' "$WORKDIR/soubor7"
	fetch_cccam_lines "https://cccamia.com/free-cccam/" 'C: [a-z][^<]*' "$WORKDIR/soubor8"
	fetch_cccam_lines "https://cccamhub.com/cccamfree/" 'C: free[^<]*' "$WORKDIR/soubor9"
	fetch_cccam_lines "https://cccamiptv.club/free-cccam/#page-content" 'C: free[^<]*' "$WORKDIR/soubor10"
	curl --max-time 8 --limit-rate 100K -s -k server.satunivers.tv/download.php?file=cccm.cfg > "$WORKDIR/soubor12" || true
	fetch_cccam_lines "https://cccamgalaxy.com/" 'C: [a-z][^<]*' "$WORKDIR/soubor13"
	fetch_cccam_lines "https://cccam-premium.pro/free-cccam/" 'C: [a-z][^<]*' "$WORKDIR/soubor18"
	fetch_cccam_lines "https://cccamfree48h.yolasite.com/server-2.php" 'C: free[^<]*' "$WORKDIR/soubor19"
	fetch_cccam_lines "https://cccam.net/freecccam" 'C: [a-z][^<]*' "$WORKDIR/soubor20"

	append_testious

	: > "$CCCAM_CFG"
	i=1
	while [ "$i" -le 28 ]; do
		cat "$WORKDIR/soubor$i" >> "$CCCAM_CFG" 2>/dev/null || true
		i=$((i + 1))
	done
	sed -i 's/c:/C:/' "$CCCAM_CFG" 2>/dev/null || true

	: > "$CCCAM_CFG_FILTERED"
	while read -r line; do
		words=$(echo "$line" | wc -w)
		if [ "$words" -gt 4 ]; then
			echo "$line" >> "$CCCAM_CFG_FILTERED"
		fi
	done < "$CCCAM_CFG"

	cp "$CCCAM_CFG_FILTERED" /etc/CCcam.cfg 2>/dev/null || true
}


merge_target_server() {
	target="$1"
	target_dir="$(dirname "$target")"
	tmp_target="/tmp/oscam_merge_$$.tmp"

	# Skip paths whose parent directory does not exist.
	[ -d "$target_dir" ] || return 0


	# Keep user-maintained lines, drop previous auto-generated block if present.
	if [ -f "$target" ]; then
		sed "/^${AUTOGEN_BEGIN}","/^${AUTOGEN_END}/d" "$target" > "$tmp_target" 2>/dev/null || cp "$target" "$tmp_target"
	else
		: > "$tmp_target"
	fi

	# Always place new fetched readers below original user lines.
	if [ -s "$tmp_target" ]; then
		echo "" >> "$tmp_target"
	fi
	echo "$AUTOGEN_BEGIN" >> "$tmp_target"
	cat "$OUTPUT_SERVER" >> "$tmp_target"
	echo "$AUTOGEN_END" >> "$tmp_target"

	cp "$tmp_target" "$target" 2>/dev/null || true
	rm -f "$tmp_target"
}

convert_to_oscam_server() {
	: > "$OUTPUT_SERVER"
	: > "$OUTPUT_NEWCAMD"

	grep -i '^C:' /etc/CCcam.cfg 2>/dev/null | while read -r line; do
		set -- $line
		server="$2"
		port="$3"
		user="$4"
		pass="$5"

		cat >> "$OUTPUT_SERVER" <<EOC
[reader]
label = $server
protocol = cccam
device = $server,$port
user = $user
password = $pass
group = 1
ccckeepalive = 1
inactivitytimeout = 30
reconnecttimeout = 5
disablecrccws = 1
disablecrccws_only_for = 0E00:000000,0500:030B00,050F00;098C:000000;09C4:000000
audisabled = 0

EOC
	done

	grep -i '^N:' /etc/CCcam.cfg 2>/dev/null | while read -r line; do
		set -- $line
		[ "$1" = "N:" ] || continue
		server="$2"
		port="$3"
		user="$4"
		pass="$5"
		shift 5
		key="$1"
		shift
		while [ "$#" -gt 0 ]; do
			key="${key}$1"
			shift
		done

		cat >> "$OUTPUT_NEWCAMD" <<EON
[reader]
label = $server
enable = 1
protocol = newcamd
key = $key
device = $server,$port
user = $user
password = $pass
group = 1
inactivitytimeout = 1
reconnecttimeout = 30
lb_weight = 100
cccversion = 2.1.2
cccmaxhops = 10
cccwantemu = 1
ccckeepalive = 1

EON
	done

	cat "$OUTPUT_NEWCAMD" >> "$OUTPUT_SERVER"
	[ -f /etc/OscamDATAx.cfg ] && cat /etc/OscamDATAx.cfg >> "$OUTPUT_SERVER"

	# If user passed an explicit target path, only update that path.
	if [ "$TARGET_SERVER" != "/tmp/server" ]; then
		merge_target_server "$TARGET_SERVER"
		echo "Updated target: $TARGET_SERVER"
		return 0
	fi

	# Otherwise update first existing/available server path only (do not overwrite all variants).
	for path in \
		/etc/tuxbox/config/oscam.server \
		/etc/tuxbox/config/oscam/oscam.server \
		/etc/tuxbox/config/oscam-emu/oscam.server \
		/etc/tuxbox/config/oscam_atv_free/oscam.server \
		/etc/tuxbox/config/oscam-stable/oscam.server \
		/var/tuxbox/config/oscam.server \
		/etc/tuxbox/config/ncam.server \
		/etc/tuxbox/config/ncam/ncam.server \
		/etc/tuxbox/config/gcam.server \
		/etc/tuxbox/config/supcam-emu/oscam.server \
		/etc/tuxbox/config/oscamicam/oscam.server \
		/etc/tuxbox/config/oscamicamnew/oscam.server
	do
		if [ -f "$path" ] || [ -d "$(dirname "$path")" ]; then
			merge_target_server "$path"
			echo "Updated target: $path"
			return 0
		fi
	done

	echo "No server target path found; generated readers kept at $OUTPUT_SERVER"
}

main() {
	if ! ensure_curl; then
		echo "curl is required but could not be installed"
		exit 1
	fi

	echo "Downloading and preparing CCcam lines..."
	build_cccam_cfg

	echo "Converting CCcam/Newcamd lines to OSCam readers..."
	convert_to_oscam_server

	if [ -x /etc/init.d/softcam ]; then
		/etc/init.d/softcam restart || true
	fi

	count="0"
	[ -f /etc/CCcam.cfg ] && count="$(wc -l < /etc/CCcam.cfg)"
	echo "SERVERS..... $count"

	cp /etc/CCcam.cfg /tmp/CCcam.cfg 2>/dev/null || true
	cleanup
}

main "$@"
exit 0
