# Emulacao de rede com tc netem

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

# apply_scenario lan | wan_loss | wan_noloss
apply_scenario() {
  local name="$1" rule="" servers=()
  tc_clear
  case "$name" in
    lan)        rule="delay 0.5ms";          servers=("$SRV_TCP" "$SRV_H3");;
    wan_loss)   rule="delay 25ms loss 2%";   servers=("$SRV_TCP" "$SRV_H3");;
    wan_noloss) rule="delay 25ms";           servers=("$SRV_H3");;
    *) echo "cenario invalido: $name"; exit 1;;
  esac
  for c in "${servers[@]}"; do
    docker exec --privileged "$c" tc qdisc add dev eth0 root netem $rule || exit 1
  done
  # netem atua so na saida (egress): sem espelhar no cliente, o RTT seria metade do desejado.
  if [ "$MIRROR_CLIENT" = 1 ]; then
    docker exec --privileged "$CLI" tc qdisc add dev eth0 root netem $rule || exit 1
  fi
  sleep 1
  log "Cenario '$name' aplicado (netem $rule). Verificacao de RTT:"
  { echo "== $name =="; docker exec "$CLI" ping -c 5 -q "$IP_H3" | tail -2; } | tee -a "$OUT/rtt_check.txt"
}
