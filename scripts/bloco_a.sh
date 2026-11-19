# Bloco A: vazao e retransmissoes TCP (iperf3, CUBIC vs BBR)

# run_iperf <id> <algoritmo> <cenario> <rep>
run_iperf() {
  local id="$1" algo="$2" scen="$3" rep="$4" jf res=""
  jf="$OUT/json/${id}_rep${rep}.json"
  for attempt in 1 2 3; do
    if docker exec "$CLI" timeout $((DURATION + 30)) iperf3 -c "$IP_TCP" -t "$DURATION" -C "$algo" -J > "$jf" 2>/dev/null; then
      res=$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1]))["end"]; print(round(e["sum_received"]["bits_per_second"]/1e6,3), e["sum_sent"]["retransmits"])' "$jf" 2>/dev/null) && break
    fi
    res=""; log "  falha em $id rep$rep (tentativa $attempt); repetindo"; sleep 5
  done
  [ -z "$res" ] && { log "ERRO: $id rep$rep falhou"; return 1; }
  set -- $res
  echo "$id,$rep,$algo,$scen,$1,$2" >> "$A_CSV"
  log "  $id rep$rep ($algo/$scen): $1 Mbps, $2 retransmissoes"
  sleep 2
}

blocoA_lan() {        # E01
  apply_scenario lan
  for r in $(seq 1 "$REPS"); do run_iperf E01 cubic LAN "$r"; done
}

blocoA_wan() {        # E02 e E03 intercalados (reduz efeito de deriva do ambiente)
  apply_scenario wan_loss
  for r in $(seq 1 "$REPS"); do
    run_iperf E02 cubic WAN_2pct "$r"
    run_iperf E03 bbr   WAN_2pct "$r"
  done
}
