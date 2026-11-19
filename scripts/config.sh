# Configuracao compartilhada (carregado por run_n3.sh)
REPS="${REPS:-5}"                     # repeticoes por teste
DURATION="${DURATION:-15}"            # duracao do fluxo iperf3 (s)
MIRROR_CLIENT="${MIRROR_CLIENT:-1}"   # 1 = replica a regra netem no cliente (RTT total correto)
KEEP_UP="${KEEP_UP:-0}"               # 1 = nao derruba os conteineres ao final

SRV_TCP=server_tcp_cc
SRV_H3=server_http3_quic
CLI=client_bench
IP_TCP=172.20.0.10
IP_H3=172.20.0.30
URL="https://${IP_H3}/obj1k.bin"

OUT=results
A_CSV="$OUT/raw_blocoA.csv"
B_CSV="$OUT/raw_blocoB.csv"
FMT='%{http_version} %{time_connect} %{time_appconnect} %{time_starttransfer}\n'
HAVE_SESS=0

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi
log() { echo "[$(date +%H:%M:%S)] $*"; }
