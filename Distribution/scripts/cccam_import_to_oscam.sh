#!/bin/sh
#
# Import free CCcam/Newcamd lines from public pages, convert them to OSCam readers
# and write/update oscam.server in common STB paths.
#
# v9: Enhanced Error Diagnostics for Return Code 1 & Improved Path Detection.

set -u

# --- CONFIGURATION ---
WORKDIR="/tmp/xtest"
CCCAM_CFG="/tmp/CCcam.cfg"
CCCAM_CFG_FILTERED="/tmp/CCcam.cfg2"
SOURCE_PAGE="$WORKDIR/CCcam"
TARGET_SERVER="/etc/tuxbox/config/oscam-emu/oscam.server"
OUTPUT_SERVER="/tmp/server.generated"
OUTPUT_NEWCAMD="/tmp/server_n"
AUTOGEN_BEGIN="# ---- OSCAM AUTO-GENERATED READERS (cccam_import_to_oscam.sh) BEGIN ----"
AUTOGEN_END="# ---- OSCAM AUTO-GENERATED READERS (cccam_import_to_oscam.sh) END ----"

# Ensure Work Directory exists
if ! mkdir -p "$WORKDIR"; then
	echo "ERROR: Could not create temporary directory $WORKDIR. Check permissions or disk space."
	exit 1
fi

cleanup() {
	echo "[DEBUG] Cleaning up temporary environment..."
	rm -f "$OUTPUT_NEWCAMD" "$OUTPUT_SERVER" "$CCCAM_CFG_FILTERED" "$SOURCE_PAGE" "$WORKDIR"/soubor* "$WORKDIR"/testious_*.tmp "$WORKDIR"/testious_page.html
	rmdir "$WORKDIR" 2>/dev/null || true
}

get_random_ua() {
	case $(( ( RANDOM % 5 )  + 1 )) in
		1) echo "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" ;;
		2) echo "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36" ;;
		3) echo "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0" ;;
		4) echo "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Edge/122.0.2365.92" ;;
		*) echo "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1" ;;
	esac
}

ensure_curl() {
	if command -v curl >/dev/null 2>&1; then return 0; fi
	
	echo "[SYSTEM] Curl not found. Attempting installation..."
	if command -v opkg >/dev/null 2>&1; then
		opkg update && opkg install curl
	elif command -v apt-get >/dev/null 2>&1; then
		apt-get update && apt-get install -y curl
	fi
	
	if ! command -v curl >/dev/null 2>&1; then
		echo "ERROR: 'curl' is required but could not be installed. Please install it manually (opkg install curl)."
		return 1
	fi
	return 0
}

fetch_cccam_lines() {
	url="$1"
	# Enhanced pattern to be more flexible with different site formats
	pattern='[CN]: [a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+ [0-9]+ [a-zA-Z0-9._-]+ [a-zA-Z0-9._-]+'
	outfile="$2"
	ua=$(get_random_ua)
	source_host=$(echo "$url" | awk -F[/:] '{print $4}')
	
	echo "[FETCH] Scanning Source: $source_host"
	
	curl --max-time 15 --limit-rate 200K -s -k -L \
		-A "$ua" \
		-e "https://www.google.com/" \
		-H "Pragma: no-cache" \
		-H "Cache-Control: no-cache" \
		"$url" > "$SOURCE_PAGE" || true
	
	grep -o -i -E "$pattern" "$SOURCE_PAGE" | sed 's/\r//g' > "$outfile" || true
	
	found=$(wc -l < "$outfile" 2>/dev/null || echo "0")
	if [ "$found" -gt 0 ]; then
		echo "  [+] Success: Found $found lines."
	else
		echo "  [-] No lines found at $source_host"
	fi
}

build_cccam_cfg() {
	: > "$CCCAM_CFG"
	
	fetch_cccam_lines "https://cccamsate.com/free" "$WORKDIR/soubor1"
	fetch_cccam_lines "https://cccamia.com/free-cccam/" "$WORKDIR/soubor2"
	fetch_cccam_lines "https://cccamhub.com/cccamfree/" "$WORKDIR/soubor3"
	fetch_cccam_lines "https://cccamiptv.club/free-cccam/" "$WORKDIR/soubor4"
	fetch_cccam_lines "https://cccamgalaxy.com/" "$WORKDIR/soubor5"
	fetch_cccam_lines "https://cccam-premium.pro/free-cccam/" "$WORKDIR/soubor6"
	fetch_cccam_lines "https://cccam.net/freecccam" "$WORKDIR/soubor8"
	fetch_cccam_lines "https://boss-cccam.com/free-cccam/" "$WORKDIR/soubor9"
	fetch_cccam_lines "https://vcccam.com/" "$WORKDIR/soubor10"
	fetch_cccam_lines "https://freerbox.com/" "$WORKDIR/soubor11"
	fetch_cccam_lines "https://supercccam.com/free-cccam/" "$WORKDIR/soubor12"
	fetch_cccam_lines "https://fastcccam.com/free-cccam/" "$WORKDIR/soubor13"
	fetch_cccam_lines "https://cccam-free.com/" "$WORKDIR/soubor14"
	fetch_cccam_lines "https://www.freecccamserver.com/" "$WORKDIR/soubor15"
	fetch_cccam_lines "https://www.cccambird.com/" "$WORKDIR/soubor16"
	fetch_cccam_lines "https://cccamfree.tv/" "$WORKDIR/soubor17"

	echo "[INFO] Consolidating and cleaning data..."
	cat "$WORKDIR"/soubor* >> "$CCCAM_CFG" 2>/dev/null
	sed -i 's/c:/C:/g; s/n:/N:/g' "$CCCAM_CFG" 2>/dev/null

	: > "$CCCAM_CFG_FILTERED"
	sort -u "$CCCAM_CFG" | while read -r line; do
		if ! echo "$line" | grep -qiE "http|purl|terms|xml|schema"; then
			echo "$line" >> "$CCCAM_CFG_FILTERED"
		fi
	done
	cp "$CCCAM_CFG_FILTERED" /etc/CCcam.cfg 2>/dev/null || true
}

convert_to_oscam_server() {
	: > "$OUTPUT_SERVER"
	: > "$OUTPUT_NEWCAMD"

	echo "-------------------------------------------------------"
	echo "        LOGGING GENERATED OSCAM READERS                "
	echo "-------------------------------------------------------"

	grep -i '^C:' /etc/CCcam.cfg 2>/dev/null | while read -r line; do
		set -- $line
		[ "$#" -lt 5 ] && continue
		server="$2"; port="$3"; user="$4"; pass="$5"
		echo "[GENERATE] CCcam -> $server"
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
		[ "$#" -lt 6 ] && continue
		server="$2"; port="$3"; user="$4"; pass="$5"
		shift 5; key="$1"; shift
		while [ "$#" -gt 0 ]; do key="${key}$1"; shift; done
		echo "[GENERATE] Newcamd -> $server"
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
	
	# Loop through all possible config paths
	for path in \
		/etc/tuxbox/config/oscam-emu/oscam.server \
		/etc/tuxbox/config/oscam.server \
		/etc/tuxbox/config/ncam.server \
		/etc/tuxbox/config/oscam/oscam.server
	do
		if [ -d "$(dirname "$path")" ]; then
			echo "[WRITE] Updating: $path"
			tmp_target="/tmp/oscam_merge_$$.tmp"
			[ -f "$path" ] && sed "/^${AUTOGEN_BEGIN}$/,/^${AUTOGEN_END}$/d" "$path" > "$tmp_target" || : > "$tmp_target"
			echo "$AUTOGEN_BEGIN" >> "$tmp_target"
			cat "$OUTPUT_SERVER" >> "$tmp_target"
			echo "$AUTOGEN_END" >> "$tmp_target"
			if cp "$tmp_target" "$path"; then
				echo "  [+] Success."
			else
				echo "  [!] Warning: Failed to write to $path. Check file permissions."
			fi
			rm -f "$tmp_target"
		fi
	done
}

restart_softcam() {
	echo "[DETACH] Handing over to background restart (15s delay)..."
	nohup sh -c "
		sleep 15
		if [ -d '/usr/emu_scripts' ]; then
			for cam_proc in oscam-emu ncam supcam ultracam; do
				if pgrep -i \"\$cam_proc\" > /dev/null; then
					EG_SCRIPT=\$(ls /usr/emu_scripts/EGcam_*.sh 2>/dev/null | grep -i \"\$cam_proc\" | head -n 1)
					if [ -n \"\$EG_SCRIPT\" ]; then
						sh \"\$EG_SCRIPT\" stop >/dev/null 2>&1
						sleep 2
						sh \"\$EG_SCRIPT\" start >/dev/null 2>&1
						exit 0
					fi
				fi
			done
		fi
		[ -x /etc/init.d/softcam ] && /etc/init.d/softcam restart >/dev/null 2>&1 || killall -9 oscam-emu ncam 2>/dev/null
	" >/dev/null 2>&1 &
}

main() {
	echo "======================================================="
	echo "      OSCAM AUTO-IMPORT v9 (ERROR DIAGNOSTICS)         "
	echo "======================================================="
	
	ensure_curl || exit 1
	
	build_cccam_cfg
	convert_to_oscam_server
	
	final_count=$(grep -c "\[reader\]" "$OUTPUT_SERVER" 2>/dev/null || echo "0")
	echo "-------------------------------------------------------"
	echo "SUCCESS: $final_count readers generated and applied."
	echo "-------------------------------------------------------"
	
	cleanup
	restart_softcam
	
	echo "[FINISH] Process complete. Refresh WebIF in 20-30 seconds."
	echo "======================================================="
}

main
exit 0
