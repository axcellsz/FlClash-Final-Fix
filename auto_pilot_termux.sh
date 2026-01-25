#!/system/bin/sh

# --- ZIVPN AUTO PILOT STANDARD ---
# Simple & Lightweight: Check -> Toggle if Fail

WORKDIR="/data/data/com.termux/files/home"
RISH="$WORKDIR/rish_test"
TARGET="http://connectivitycheck.gstatic.com/generate_204"

# Waktu tunggu (detik)
TIMEOUT=5
INTERVAL=10

echo "--- Auto Pilot Standard Started ---"

check_internet() {
    # Cek HTTP Code (204 = Sukses)
    curl -I -s -L --connect-timeout $TIMEOUT --max-time $TIMEOUT -w "%{http_code}" -o /dev/null "$TARGET"
}

toggle_airplane() {
    echo "   -> [RESET] Toggling Airplane Mode..."
    $RISH -c "cmd connectivity airplane-mode enable"
    sleep 3
    $RISH -c "cmd connectivity airplane-mode disable"
    echo "   -> [RESET] Done. Waiting for signal..."
    sleep 10
}

while true; do
    STATUS=$(check_internet)
    
    if [ "$STATUS" = "204" ] || [ "$STATUS" = "200" ]; then
        echo -ne "\r[$(date '+%H:%M:%S')] 🟢 Internet OK ($STATUS)   "
    else
        echo ""
        echo "[$(date '+%H:%M:%S')] 🔴 Connection Lost ($STATUS)!"
        toggle_airplane
    fi
    
    sleep $INTERVAL
done
