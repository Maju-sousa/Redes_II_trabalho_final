#!/usr/bin/env bash
# run_n3.sh - TP3 (N3) Redes II: CUBIC vs BBR e HTTP/2 vs HTTP/3 (cold / warm)
# Orquestrador: aplica tc netem, executa os 6 testes x REPS repeticoes, exporta CSV/JSON,
# gera graficos/tabelas (analysis/analyze.py) e limpa o ambiente ao final.
# Opcoes (variaveis de ambiente): REPS=5  DURATION=15  MIRROR_CLIENT=1  KEEP_UP=0
set -uo pipefail
cd "$(dirname "$0")"

source scripts/config.sh
source scripts/ambiente.sh
source scripts/netem.sh
source scripts/bloco_a.sh
source scripts/bloco_b.sh

trap cleanup EXIT

main() {
  prepare_files
  setup
  echo "id,rep,algoritmo,cenario,vazao_mbps,retransmissoes" > "$A_CSV"
  echo "id,rep,modo,cenario,http_version,connect_ms,appconnect_ms,ttfb_ms" > "$B_CSV"
  : > "$OUT/rtt_check.txt"

  log "=== Bloco A / LAN (E01) ===";                    blocoA_lan
  log "=== Bloco A / WAN com perda (E02 e E03) ===";    blocoA_wan
  log "=== Bloco B / WAN sem perda (E04, E05, E06) ==="; blocoB_wan_sem_perda

  log "Gerando estatisticas, graficos e tabelas"
  python3 analysis/analyze.py
  log "Concluido. Dados em $OUT/, figuras em figures/, tabelas em report/"
}
main
