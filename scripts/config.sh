# Configuracao compartilhada 
REPS="${REPS:-5}"                     
DURATION="${DURATION:-15}"           
MIRROR_CLIENT="${MIRROR_CLIENT:-1}"   
KEEP_UP="${KEEP_UP:-0}"               

SRV_TCP=server_tcp_cc
SRV_H3=server_http3_quic
CLI=client_bench
IP_TCP=172.20.0.10
IP_H3=172.20.0.30
URL="https://${IP_H3}/obj1k.bin"

OUT=results
A_CSV="$OUT/raw_blocoA.csv"
B_CSV="$OUT/raw_blocoB.csv"
FAIL_LOG="$OUT/falhas.log"            

FMT='%{http_version} %{time_connect} %{time_appconnect} %{time_starttransfer}\n'
FMT_ED='%{http_version} %{time_connect} %{time_appconnect} %{time_starttransfer} %{tls_earlydata}\n'

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
log() { echo "[$(date +%H:%M:%S)] $*"; }

SESS_FILE=/tmp/sess.txt
HAVE_TICKET=0     # 1 = curl grava/reusa ticket TLS (--ssl-sessions)  -> mede E06b
HAVE_0RTT=0       # 1 = curl enviou early data (tls_earlydata > 0)    -> mede E06c (0-RTT de verdade)