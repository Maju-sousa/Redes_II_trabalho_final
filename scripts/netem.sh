
tc_clear() {
  for c in "$SRV_TCP" "$SRV_H3" "$CLI"; do
    docker exec --privileged "$c" tc qdisc del dev eth0 root 2>/dev/null || true
  done
}

cleanup() {
  log "Limpeza: removendo regras tc netem"
  tc_clear
  if [ "$KEEP_UP" != 1 ]; then $DC down >/dev/null 2>&1; fi
}

tc_snapshot() {  
  {
    echo "== $1 $(date +%T) =="
    for c in "$CLI" "$SRV_TCP"; do echo "-- $c"; docker exec "$c" tc -s qdisc show dev eth0; done
  } >> "$OUT/tc_stats.txt"
}

apply_scenario() {
  local name="$1" rule="" servers=() esp
  tc_clear
  case "$name" in
    lan)        rule="delay 0.5ms";          servers=("$SRV_TCP" "$SRV_H3"); esp="delay (499|500)us";;
    wan_loss)   rule="delay 25ms loss 2%";   servers=("$SRV_TCP" "$SRV_H3"); esp="delay 25ms";;
    wan_noloss) rule="delay 25ms";           servers=("$SRV_H3");            esp="delay 25ms";;
    *) echo "cenario invalido: $name"; exit 1;;
  esac
  for c in "${servers[@]}"; do
    docker exec --privileged "$c" tc qdisc add dev eth0 root netem $rule || exit 1
  done
  # netem atua so na saida (egress): sem espelhar no cliente, o RTT seria metade do desejado.
  if [ "$MIRROR_CLIENT" = 1 ]; then
    docker exec --privileged "$CLI" tc qdisc add dev eth0 root netem $rule || exit 1
  fi

  # Confere que a regra realmente ativa e a esperada (atraso e, no WAN com perda, loss 2%; nos demais, sem loss)
  local alvos=("${servers[@]}") q
  [ "$MIRROR_CLIENT" = 1 ] && alvos+=("$CLI")
  for c in "${alvos[@]}"; do
    q=$(docker exec "$c" tc qdisc show dev eth0)
    grep -Eq "$esp" <<< "$q" || { echo "netem incorreto em $c (esperado '$esp'): $q"; exit 1; }
    if [ "$name" = wan_loss ]; then
      grep -q "loss 2%" <<< "$q" || { echo "netem sem 'loss 2%' em $c: $q"; exit 1; }
    else
      ! grep -q "loss" <<< "$q" || { echo "netem com loss inesperado em $c: $q"; exit 1; }
    fi
  done

  sleep 1
  log "Cenario '$name' aplicado (netem $rule). Verificacao de RTT:"
  { echo "== $name =="; docker exec "$CLI" ping -c 10 -q "$IP_H3" | tail -2; } | tee -a "$OUT/rtt_check.txt"
}