#!/usr/bin/env bash
# run_n3.sh - TP3 (N3) Redes II: CUBIC vs BBR e HTTP/2 vs HTTP/3 (cold / reuso / retomada / 0-RTT)
# Orquestrador: aplica tc netem, executa os testes x REPS repeticoes, valida, gera graficos/tabelas e limpa.
# Opcoes: REPS=5 DURATION=15 MIRROR_CLIENT=1 KEEP_UP=0 PERMITIR_SEM_0RTT=0 PULAR_0RTT=0
set -uo pipefail
cd "$(dirname "$0")"

source scripts/config.sh
source scripts/ambiente.sh
source scripts/netem.sh
source scripts/bloco_a.sh
source scripts/bloco_b.sh

trap cleanup EXIT
RC=0

main() {
  prepare_files
  setup
  echo "id,rep,algoritmo,cenario,vazao_mbps,retransmissoes" > "$A_CSV"
  echo "id,rep,modo,cenario,http_version,connect_ms,appconnect_ms,ttfb_ms,earlydata_bytes" > "$B_CSV"
  : > "$OUT/rtt_check.txt"
  : > "$FAIL_LOG"

  log "=== Bloco A / LAN (E01) ===";                              blocoA_lan
  log "=== Bloco A / WAN com perda (E02 e E03) ===";              blocoA_wan
  log "=== Bloco B / WAN sem perda (E04, E05, E06a/b/c) ===";     blocoB_wan_sem_perda

  log "Validando a execucao"
  local flags=()
  [ "${PERMITIR_SEM_0RTT:-0}" = 1 ] && flags+=(--permitir-sem-0rtt)
  if ! python3 analysis/validar.py --reps "$REPS" --duracao "$DURATION" ${flags[@]+"${flags[@]}"}; then
    log "EXECUCAO INVALIDA: nao use estes resultados (veja as mensagens acima)"
    RC=1
    return
  fi

  log "Gerando estatisticas, graficos e tabelas"
  python3 analysis/analyze.py || { RC=1; return; }
  log "Concluido. Dados em $OUT/, figuras em figures/, tabelas em report/"
}

main
exit $RC
