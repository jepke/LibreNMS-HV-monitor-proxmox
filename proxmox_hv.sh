#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Proxmox HV Monitor Script (Fully Modular)
# -----------------------------------------------------------------------------

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-V)
      VERBOSE=1
      ;;
  esac
done

###############################################################################
# UTILITY FUNCTIONS
###############################################################################
json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

map_status_int() {
  case "$1" in
    running)            echo 1 ;;
    blocked)            echo 2 ;;
    paused)             echo 3 ;;
    shutdown)           echo 4 ;;
    stopped)            echo 5 ;;
    crashed)            echo 6 ;;
    pmsuspended)        echo 7 ;;
    off)                echo 8 ;;
    maintenance)        echo 9 ;;
    unknown)            echo 10 ;;
    *)                  echo 0 ;;
  esac
}

###############################################################################
# ENV & SETUP
###############################################################################
NODE="$(hostname -s)"
HV_STRING="proxmox"

[ $VERBOSE -eq 1 ] && echo -e "DEBUG: Local node name = '$NODE' (via hostname -s)\n" 1>&2

declare -A VMS

declare -A TOTALS=(
  [usertime]=0
  [pmem]=0
  [oublk]=0
  [minflt]=0
  [pcpu]=0
  [mem_alloc]=0
  [nvcsw]=0
  [snaps]=0
  [rss]=0
  [snaps_size]=0
  [cpus]=0
  [cow]=0
  [nivcsw]=0
  [systime]=0
  [vsz]=0
  [etimes]=0
  [majflt]=0
  [inblk]=0
  [nswap]=1000
  [on]=0
  [off]=0
  [off_hard]=0
  [off_soft]=0
  [unknown]=0
  [paused]=0
  [crashed]=0
  [blocked]=0
  [nostate]=0
  [pmsuspended]=0
  [rbytes]=0
  [rtime]=0
  [rreqs]=0
  [wbytes]=0
  [wtime]=0
  [wreqs]=0
  [disk_alloc]=0
  [disk_in_use]=0
  [disk_on_disk]=0
  [ftime]=0
  [freqs]=0
  [ipkts]=0
  [ierrs]=0
  [ibytes]=0
  [idrop]=0
  [opkts]=0
  [oerrs]=0
  [obytes]=0
  [odrop]=0
  [coll]=0
)

###############################################################################
# FETCH & PARSE DATA
###############################################################################
[ $VERBOSE -eq 1 ] && echo "DEBUG: Gathering cluster VM JSON from pvesh..." 1>&2
CLUSTER_JSON="$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null || true)"
[ $VERBOSE -eq 1 ] && echo "DEBUG: cluster JSON = " 1>&2
[ $VERBOSE -eq 1 ] && echo -e "$CLUSTER_JSON\n" 1>&2

[ $VERBOSE -eq 1 ] && echo "DEBUG: Filtering cluster JSON for type=qemu and node=$NODE..." 1>&2
FILTERED_VMS=$(echo "$CLUSTER_JSON" | jq -c '.[] | select(.type=="qemu") | select(.node=="'"$NODE"'")')

###############################################################################
# MAIN VM LOOP
###############################################################################
while IFS= read -r VM_LINE; do
  [ $VERBOSE -eq 1 ] && echo "DEBUG: Processing VM_LINE => $VM_LINE" 1>&2

  IN_VMID=$(echo "$VM_LINE"      | jq -r '.vmid')
  IN_NAME=$(echo "$VM_LINE"      | jq -r '.name')

  CURRENT_STATUS="$(pvesh get /nodes/$NODE/qemu/$IN_VMID/status/current --output-format json 2>/dev/null || true)"
  IN_STATUS=$(echo "$CURRENT_STATUS"    | jq -r '.qmpstatus')

  IN_CPU_FRAC=$(echo "$VM_LINE"         | jq -r '.cpu // 0')
  IN_MEM_USED=$(echo "$CURRENT_STATUS"  | jq -r '.mem // 0')
  IN_MEM_FREE=$(echo "$CURRENT_STATUS"  | jq -r '.ballooninfo.free_mem // 0')
  IN_MEM_ALLOC=$(echo "$CURRENT_STATUS" | jq -r '.ballooninfo.total_mem // 0')
  IN_MAJFLT=$(echo "$CURRENT_STATUS"    | jq -r '.ballooninfo.major_page_faults // 0')
  IN_MINFLT=$(echo "$CURRENT_STATUS"    | jq -r '.ballooninfo.minor_page_faults // 0')
  IN_MAXCPU=$(echo "$VM_LINE"           | jq -r '.maxcpu // 1')

  IN_DISK_ALLOC=$(echo "$VM_LINE"  | jq -r '.maxdisk // 0')
  IN_DISK_IN_USE=$(echo "$VM_LINE" | jq -r '.disk // 0')
  IN_DISK_READ=$(echo "$VM_LINE"   | jq -r '.diskread // 0')
  IN_DISK_WRITE=$(echo "$VM_LINE"  | jq -r '.diskwrite // 0')
  IN_NET_IN=$(echo "$VM_LINE"      | jq -r '.netin // 0')
  IN_NET_OUT=$(echo "$VM_LINE"     | jq -r '.netout // 0')

  [ $VERBOSE -eq 1 ] && echo "DEBUG: => VMID=$IN_VMID, NAME=$IN_NAME, STATUS=$IN_STATUS" 1>&2

  local_status_int=$(map_status_int "$IN_STATUS")
  if [ "$local_status_int" -eq 1 ]; then
    (( TOTALS[on]++ ))
  elif [ "$local_status_int" -eq 2 ]; then
    (( TOTALS[blocked]++ ))
  elif [ "$local_status_int" -eq 3 ]; then
    (( TOTALS[paused]++ ))
  elif [ "$local_status_int" -eq 4 ]; then
    (( TOTALS[off_soft]++ ))
  elif [ "$local_status_int" -eq 5 ]; then
    (( TOTALS[off]++ ))
  elif [ "$local_status_int" -eq 6 ]; then
    (( TOTALS[crashed]++ ))
  elif [ "$local_status_int" -eq 7 ]; then
    (( TOTALS[blocked]++ ))
  elif [ "$local_status_int" -eq 8 ]; then
    (( TOTALS[off_hard]++ ))
  elif [ "$local_status_int" -eq 9 ]; then
    (( TOTALS[blocked]++ ))
  else
    (( TOTALS[unknown]++ ))
  fi

  local_pid="$(echo "$CURRENT_STATUS"   | jq -r '.pid // 0')"
  [ $VERBOSE -eq 1 ] && echo "DEBUG: => Checking VMID=$IN_VMID => PID=$local_pid" 1>&2

  declare -A VMINFO=(
    [usertime]=0
    [pmem]=0
    [oublk]=0
    [minflt]=0
    [pcpu]=0
    [mem_alloc]=0
    [nvcsw]=0
    [snaps]=0
    [rss]=0
    [snaps_size]=0
    [cpus]=0
    [cow]=0
    [nivcsw]=0
    [systime]=0
    [vsz]=0
    [etimes]=0
    [majflt]=0
    [inblk]=0
    [nswap]=0
    [status_int]=0
    [rbytes]=0
    [rtime]=0
    [rreqs]=0
    [wbytes]=0
    [wtime]=0
    [wreqs]=0
    [disk_alloc]=0
    [disk_in_use]=0
    [disk_on_disk]=0
    [ftime]=0
    [freqs]=0
    [ipkts]=0
    [ierrs]=0
    [ibytes]=0
    [idrop]=0
    [opkts]=0
    [oerrs]=0
    [obytes]=0
    [odrop]=0
    [coll]=0
  )

  VMINFO[cpus]="$IN_MAXCPU"
  VMINFO[status_int]="$local_status_int"
  VMINFO[pcpu]=$(awk -v frac="$IN_CPU_FRAC" 'BEGIN { printf "%.2f", frac*100 }')
  VMINFO[rss]="$IN_MEM_USED"
  VMINFO[mem_alloc]="$IN_MEM_ALLOC"
  if [ "${VMINFO[mem_alloc]}" -gt 0 ]; then
    VMINFO[pmem]=$(awk -v used="${VMINFO[rss]}" -v alloc="${VMINFO[mem_alloc]}" 'BEGIN {
      printf "%d", (used/alloc)*100
    }')
  fi

  VMINFO[disk_alloc]="$IN_DISK_ALLOC"
  VMINFO[disk_in_use]="$IN_DISK_IN_USE"
  VMINFO[rbytes]="$IN_DISK_READ"
  VMINFO[wbytes]="$IN_DISK_WRITE"

  VMINFO[ibytes]="$IN_NET_IN"
  VMINFO[obytes]="$IN_NET_OUT"
  VMINFO[minflt]="$IN_MINFLT"
  VMINFO[majflt]="$IN_MAJFLT"

  if [[ -n "$local_pid" && -r "/proc/$local_pid/stat" ]]; then
    CLK_TCK=$(getconf CLK_TCK)
    read -ra FIELDS < "/proc/$local_pid/stat"

    local_utime="${FIELDS[13]}"
    local_stime="${FIELDS[14]}"
    local_starttime="${FIELDS[21]}"

    VMINFO[usertime]=$(awk -v u="$local_utime" -v hz="$CLK_TCK" 'BEGIN { printf "%d", u/hz }')
    VMINFO[systime]=$(awk -v s="$local_stime" -v hz="$CLK_TCK" 'BEGIN { printf "%d", s/hz }')

    if [[ -r "/proc/$local_pid/status" ]]; then
      local_vol=$(awk '/^voluntary_ctxt_switches:/ {print $2}' "/proc/'$local_pid'/status" 2>/dev/null)
      local_nonvol=$(awk '/^nonvoluntary_ctxt_switches:/ {print $2}' "/proc/'$local_pid'/status" 2>/dev/null)
      [[ -z "$local_vol" ]] && local_vol=0
      [[ -z "$local_nonvol" ]] && local_nonvol=0
      VMINFO[nvcsw]="$local_vol"
      VMINFO[nivcsw]="$local_nonvol"
    fi

    SYS_UP_S=$(awk '{print $1}' /proc/uptime)
    SYS_UP_TICKS=$(awk -v s="$SYS_UP_S" -v hz="$CLK_TCK" 'BEGIN { printf "%d", s*hz }')
    if [ "$local_starttime" -gt 0 ] && [ "$SYS_UP_TICKS" -gt "$local_starttime" ]; then
      VMINFO[etimes]=$(awk -v up="$SYS_UP_TICKS" -v st="$local_starttime" -v hz="$CLK_TCK" \
        'BEGIN { printf "%d", (up - st)/hz }')
    fi
  else
    [ $VERBOSE -eq 1 ] && echo "DEBUG: => No valid PID or /proc/$local_pid/stat not readable. Skipping advanced metrics." 1>&2
  fi

  [ $VERBOSE -eq 1 ] && echo "DEBUG: => Final VMINFO for VMID=$IN_VMID with declared fields:" 1>&2
  [ $VERBOSE -eq 1 ] && declare -p VMINFO 1>&2

  # (E) Gather 'disks' data from CURRENT_STATUS_BLOCKSTAT
  [ $VERBOSE -eq 1 ] && echo "DEBUG: Gathering disk info from blockstat for VMID=$IN_VMID..." 1>&2
  CURRENT_STATUS_BLOCKSTAT="$(echo "$CURRENT_STATUS" | jq -r '.blockstat')"

  if [ -n "$CURRENT_STATUS_BLOCKSTAT" ] && [ "$CURRENT_STATUS_BLOCKSTAT" != "null" ]; then
    disks_json="{"
    disk_idx=0
    DEV_KEYS="$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r 'keys[]')"
    while IFS= read -r DEV_NAME; do
      [ $VERBOSE -eq 1 ] && echo "DEBUG: processing disk device $DEV_NAME" 1>&2
      rd_bytes=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"rd_bytes\" // 0")
      rd_ops=$(echo "$CURRENT_STATUS_BLOCKSTAT"   | jq -r ".\"$DEV_NAME\".\"rd_operations\" // 0")
      rd_time_ns=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"rd_total_time_ns\" // 0")

      wr_bytes=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"wr_bytes\" // 0")
      wr_ops=$(echo "$CURRENT_STATUS_BLOCKSTAT"   | jq -r ".\"$DEV_NAME\".\"wr_operations\" // 0")
      wr_time_ns=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"wr_total_time_ns\" // 0")

      flush_ops=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"flush_operations\" // 0")
      flush_time_ns=$(echo "$CURRENT_STATUS_BLOCKSTAT" | jq -r ".\"$DEV_NAME\".\"flush_total_time_ns\" // 0")

      DISK_IN_USE=0
      DISK_ON_DISK=0
      DISK_ALLOC=0
      DISK_RBYTES=$rd_bytes
      DISK_RTIME=$rd_time_ns
      DISK_RREQS=$rd_ops
      DISK_WBYTES=$wr_bytes
      DISK_WTIME=$wr_time_ns
      DISK_WREQS=$wr_ops
      DISK_FTIME=$flush_time_ns
      DISK_FREQS=$flush_ops

      disk_obj="\"in_use\": $DISK_IN_USE, \"on_disk\": $DISK_ON_DISK, \"alloc\": $DISK_ALLOC,"
      disk_obj+=" \"rbytes\": $DISK_RBYTES, \"rtime\": $DISK_RTIME, \"rreqs\": $DISK_RREQS,"
      disk_obj+=" \"wbytes\": $DISK_WBYTES, \"wtime\": $DISK_WTIME, \"wreqs\": $DISK_WREQS,"
      disk_obj+=" \"ftime\": $DISK_FTIME, \"freqs\": $DISK_FREQS"

      [ $disk_idx -gt 0 ] && disks_json+=","
      disks_json+="\"$DEV_NAME\": { $disk_obj }"
      disk_idx=$(( disk_idx + 1 ))
    done <<< "$DEV_KEYS"
    disks_json+="}"
  else
    [ $VERBOSE -eq 1 ] && echo "DEBUG: blockstat is empty or null, using empty disks object." 1>&2
    disks_json="{}"
  fi

  # (D) Gather 'ifs' data from QEMU Guest Agent (network-get-interfaces)
  [ $VERBOSE -eq 1 ] && echo -e "\n\nDEBUG: Gathering NIC data via QEMU Guest Agent for VMID=$IN_VMID..." 1>&2
  agent_ifinfo="$(pvesh get /nodes/$NODE/qemu/$IN_VMID/agent/network-get-interfaces --output-format json 2>/dev/null || true)"
  if [ -n "$agent_ifinfo" ]; then
    [ $VERBOSE -eq 1 ] && echo "DEBUG: agent returned: $agent_ifinfo" 1>&2
    ifs_json="{"
    idx=0
    AGENT_IFINFO="$(echo "$agent_ifinfo" | jq -c '.result[]')"
    while IFS= read -r IF_LINE; do
      IF_NAME=$(echo "$IF_LINE" | jq -r '.name')
      IF_MAC=$(echo "$IF_LINE" | jq -r '.["hardware-address"]')

      IF_RX_BYTES=$(echo "$IF_LINE" | jq -r '.statistics["rx-bytes"] // 0')
      IF_RX_PACKETS=$(echo "$IF_LINE" | jq -r '.statistics["rx-packets"] // 0')
      IF_RX_ERRS=$(echo "$IF_LINE" | jq -r '.statistics["rx-errs"] // 0')
      IF_RX_DROP=$(echo "$IF_LINE" | jq -r '.statistics["rx-dropped"] // 0')

      IF_TX_BYTES=$(echo "$IF_LINE" | jq -r '.statistics["tx-bytes"] // 0')
      IF_TX_PACKETS=$(echo "$IF_LINE" | jq -r '.statistics["tx-packets"] // 0')
      IF_TX_ERRS=$(echo "$IF_LINE" | jq -r '.statistics["tx-errs"] // 0')
      IF_TX_DROP=$(echo "$IF_LINE" | jq -r '.statistics["tx-dropped"] // 0')

      IF_PARENT=""

      if_obj="\"mac\": \"$IF_MAC\", \"parent\": \"$IF_PARENT\", \"if\": \"$IF_NAME\","
      if_obj+=" \"ipkts\": $IF_RX_PACKETS, \"ierrs\": $IF_RX_ERRS, \"ibytes\": $IF_RX_BYTES,"
      if_obj+=" \"idrop\": $IF_RX_DROP, \"opkts\": $IF_TX_PACKETS, \"oerrs\": $IF_TX_ERRS,"
      if_obj+=" \"obytes\": $IF_TX_BYTES, \"odrop\": $IF_TX_DROP, \"coll\": 0"

      [ $idx -gt 0 ] && ifs_json+=","
      ifs_json+="\"$IF_NAME\": { $if_obj }"
      idx=$(( idx+1 ))
    done <<< "$AGENT_IFINFO"
    ifs_json+="}"
  else
    [ $VERBOSE -eq 1 ] && echo "DEBUG: agent returned no NIC info, using empty object." 1>&2
    ifs_json="{}"
  fi

  json_part=""
  for k in "${!VMINFO[@]}"; do
    json_part+="\"$k\": ${VMINFO[$k]},"
  done

  json_part+="\"disks\": $disks_json,"
  json_part+="\"ifs\": $ifs_json,"
  json_part="${json_part%,}"

  ESCAPED_NAME=$(echo "$IN_NAME" | json_escape)
  VMS["$ESCAPED_NAME"]="{${json_part}}"

done <<< "$FILTERED_VMS"

[ $VERBOSE -eq 1 ] && echo "DEBUG: Gathering physical disks from pvesh and /proc/diskstats..." 1>&2
IN_DISK_LIST="$(pvesh get /nodes/$NODE/disks/list --output-format json 2>/dev/null || true)"
declare -A DISK_STATS

while read -r major minor devname r_comp r_merge r_sect r_time \
                           w_comp w_merge w_sect w_time rest; do
  [[ "$devname" =~ ^(loop|ram|dm-|zd) ]] && continue
  DISK_STATS["$devname,rbytes"]=$((r_sect * 512))
  DISK_STATS["$devname,rtime"]=$r_time
  DISK_STATS["$devname,rreqs"]=$r_comp
  DISK_STATS["$devname,wbytes"]=$((w_sect * 512))
  DISK_STATS["$devname,wtime"]=$w_time
  DISK_STATS["$devname,wreqs"]=$w_comp
done < /proc/diskstats

IFS_LINES="$(echo $IN_DISK_LIST | jq -c '.[]')"
VMdisks_json="{"
disk_idx=0

while IFS= read -r DISK_LINE; do
  IN_DEVPATH=$(echo "$DISK_LINE" | jq -r '.devpath // empty')
  [[ -z "$IN_DEVPATH" ]] && continue

  IN_NAME="${IN_DEVPATH##*/}"
  IN_SIZE=$(echo "$DISK_LINE" | jq -r '.size // "0"')
  [[ "$IN_SIZE" =~ ^[0-9]+$ ]] || IN_SIZE=0

  OUT_ALLOC="$IN_SIZE"
  OUT_ON_DISK="$IN_SIZE"
  OUT_IN_USE="$IN_SIZE"

  OUT_RBYTES="${DISK_STATS["$IN_NAME,rbytes"]:-0}"
  OUT_RTIME="${DISK_STATS["$IN_NAME,rtime"]:-0}"
  OUT_RREQS="${DISK_STATS["$IN_NAME,rreqs"]:-0}"
  OUT_WBYTES="${DISK_STATS["$IN_NAME,wbytes"]:-0}"
  OUT_WTIME="${DISK_STATS["$IN_NAME,wtime"]:-0}"
  OUT_WREQS="${DISK_STATS["$IN_NAME,wreqs"]:-0}"
  OUT_FTIME=0
  OUT_FREQS=0

  disk_obj="\"in_use\": $OUT_IN_USE, \"on_disk\": $OUT_ON_DISK, \"alloc\": $OUT_ALLOC,"
  disk_obj+=" \"rbytes\": $OUT_RBYTES, \"rtime\": $OUT_RTIME, \"rreqs\": $OUT_RREQS,"
  disk_obj+=" \"wbytes\": $OUT_WBYTES, \"wtime\": $OUT_WTIME, \"wreqs\": $OUT_WREQS,"
  disk_obj+=" \"ftime\": $OUT_FTIME, \"freqs\": $OUT_FREQS"

  [[ $disk_idx -gt 0 ]] && VMdisks_json+=","
  VMdisks_json+="\"$IN_NAME\": { $disk_obj }"
  disk_idx=$((disk_idx+1))
done <<< "$IFS_LINES"

VMdisks_json+="}"

###############################################################################
# PROCESS TOTALS
###############################################################################
[ $VERBOSE -eq 1 ] && echo -e "\nDEBUG: Gathering node usage for TOT..." 1>&2
CLUSTER_INFO="$(pvesh get /cluster/resources --type node --output-format json 2>/dev/null || true)"
THIS_NODE="$(pvesh get /nodes/$NODE/status --output-format json 2>/dev/null || true)"

THIS_CLUSTER="$(echo "$CLUSTER_INFO" | jq -c '.[] | select(.node=="'"$NODE"'")')"

IN_NODE_CPU_FRAC="$(echo "$THIS_CLUSTER"   | jq -r '.cpu // 0')"
IN_NODE_MEM_USED="$(echo "$THIS_NODE"   | jq -r '.memory.used // 0')"
IN_NODE_MEM_MAX="$(echo "$THIS_NODE"    | jq -r '.memory.total // 0')"
IN_NODE_UPTIME="$(echo "$THIS_NODE"     | jq -r '.uptime // 0')"
IN_NODE_DISK_ALLOC="$(echo "$THIS_NODE" | jq -r '.rootfs.total // 0')"
IN_NODE_DISK_INUSE="$(echo "$THIS_NODE" | jq -r '.rootfs.used // 0')"

[ $VERBOSE -eq 1 ] && echo "DEBUG: => node usage: CPU frac=$IN_NODE_CPU_FRAC, memUsed=$IN_NODE_MEM_USED, memMax=$IN_NODE_MEM_MAX" 1>&2

OUT_NODE_PCPU=$(awk -v f="$IN_NODE_CPU_FRAC" 'BEGIN { printf "%.2f", f*100 }')
OUT_NODE_RSS="$IN_NODE_MEM_USED"
OUT_NODE_MEM_ALLOC="$IN_NODE_MEM_MAX"
OUT_NODE_PMEM=0
OUT_NODE_ETIMES="$IN_NODE_UPTIME"
OUT_NODE_DISK_ALLOC="$IN_NODE_DISK_ALLOC"
OUT_NODE_DISK_INUSE="$IN_NODE_DISK_INUSE"

if [ "$OUT_NODE_MEM_ALLOC" -gt 0 ]; then
  OUT_NODE_PMEM=$(awk -v used="$OUT_NODE_RSS" -v alloc="$OUT_NODE_MEM_ALLOC" \
    'BEGIN { printf "%.2f", (used/alloc)*100 }')
fi

TOTALS[pcpu]="$OUT_NODE_PCPU"
TOTALS[rss]="$OUT_NODE_RSS"
TOTALS[mem_alloc]="$OUT_NODE_MEM_ALLOC"
TOTALS[pmem]="$OUT_NODE_PMEM"
TOTALS[etimes]="$OUT_NODE_ETIMES"
TOTALS[disk_alloc]="$OUT_NODE_DISK_ALLOC"
TOTALS[disk_in_use]="$OUT_NODE_DISK_INUSE"

[ $VERBOSE -eq 1 ] && echo "DEBUG: Getting primary eth interface..." 1>&2
PROX_NET_JSON="$(pvesh get /nodes/$NODE/network --output-format json 2>/dev/null || true)"
ETH_IFACE=$(echo "$PROX_NET_JSON" | jq -r '.[] | select(.type=="eth") | select(.active==1) | .iface' | head -n1)

if [ -n "$ETH_IFACE" ]; then
  [ $VERBOSE -eq 1 ] && echo "DEBUG: Using eth interface: $ETH_IFACE" 1>&2
  while read -r line; do
    [[ "$line" =~ ^\ *Inter|^\ *face ]] && continue
    IF_LINE=$(echo "$line" | sed 's/^[[:space:]]*//')
    IF_NAME=$(echo "$IF_LINE" | cut -d: -f1)
    [[ "$IF_NAME" == "$ETH_IFACE" ]] || continue

    read -ra F <<< "$(echo "$IF_LINE" | cut -d: -f2-)"
    TOTALS[ipkts]=${F[1]}
    TOTALS[ierrs]=${F[2]}
    TOTALS[ibytes]=${F[0]}
    TOTALS[idrop]=${F[3]}
    TOTALS[opkts]=${F[9]}
    TOTALS[oerrs]=${F[10]}
    TOTALS[obytes]=${F[8]}
    TOTALS[odrop]=${F[11]}
    TOTALS[coll]=0
    [ $VERBOSE -eq 1 ] && echo "DEBUG: Loaded /proc/net/dev stats for $IF_NAME" 1>&2
  done < /proc/net/dev
else
  [ $VERBOSE -eq 1 ] && echo "DEBUG: No active eth interface found on this node." 1>&2
fi

[ $VERBOSE -eq 1 ] && echo -e "\n\nDEBUG: Done reading cluster and VMs. Now building final JSON..." 1>&2

###############################################################################
# BUILD FINAL JSON
###############################################################################
TOTALS_JSON=""
for k in "${!TOTALS[@]}"; do
  TOTALS_JSON+="\"$k\": ${TOTALS[$k]},"
done
TOTALS_JSON="{${TOTALS_JSON%,}}"

VMS_JSON=""
for vm_name in "${!VMS[@]}"; do
  VMS_JSON+="\"$vm_name\": ${VMS[$vm_name]},"
done
VMS_JSON="{${VMS_JSON%,}}"

VMdisks_JSON="$VMdisks_json"
VMifs_JSON="{}"
VMstatus_JSON="{}"

DATA_JSON="$(cat <<EOF
{
  "hv": "$(echo "$HV_STRING" | json_escape)",
  "totals": $TOTALS_JSON,
  "VMs": $VMS_JSON,
  "VMdisks": $VMdisks_JSON,
  "VMifs": $VMifs_JSON,
  "VMstatus": $VMstatus_JSON
}
EOF
)"

VERSION="1"
ERROR="0"
ERROR_STRING=""

[ $VERBOSE -eq 1 ] && echo "DEBUG: Final data =>" 1>&2
[ $VERBOSE -eq 1 ] && printf '%s\n' "$DATA_JSON" | jq -C . 1>&2

cat <<EOF > /etc/snmp/snmpd.conf.d/proxmox_hvmonitor.json
{
  "version": $VERSION,
  "error": $ERROR,
  "errorString": "$(echo "$ERROR_STRING" | json_escape)",
  "data": $DATA_JSON
}
EOF

[ $VERBOSE -eq 1 ] && echo "DEBUG: Wrote /etc/snmp/snmpd.conf.d/proxmox_hvmonitor.json. Done." 1>&2
