# Bloco B: TTFB de HTTP/2, HTTP/3 cold e HTTP/3 warm (curl)

# record_b <id> <rep> <modo> <cenario>   (le "versao connect appconnect ttfb" em segundos do stdin)
record_b() {
  awk -v id="$1" -v rep="$2" -v m="$3" -v s="$4" \
    '{printf "%s,%s,%s,%s,%s,%.3f,%.3f,%.3f\n", id,rep,m,s,$1,$2*1000,$3*1000,$4*1000}' >> "$B_CSV"
}

run_blocoB_rep() {    # <rep>
  local rep="$1" out
  out=$(docker exec "$CLI" curl -k -s --http2 -o /dev/null -w "$FMT" "$URL")
  [ "${out%% *}" = "2" ] || log "  AVISO E04: versao HTTP = ${out%% *} (esperado 2)"
  record_b E04 "$rep" "HTTP/2 (TCP+TLS)" WAN_0 <<< "$out"

  out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null -w "$FMT" "$URL")
  [ "${out%% *}" = "3" ] || log "  AVISO E05: versao HTTP = ${out%% *} (esperado 3)"
  record_b E05 "$rep" "HTTP/3 Cold (1-RTT)" WAN_0 <<< "$out"

  # E06: duas requisicoes na mesma chamada; a 2a reaproveita a conexao QUIC ja aberta.
  out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null -o /dev/null -w "$FMT" "$URL" "$URL")
  record_b E06_primeira "$rep" "HTTP/3 (1a req. da sessao)" WAN_0 <<< "$(echo "$out" | sed -n 1p)"
  record_b E06 "$rep" "HTTP/3 Warm (conexao reutilizada)" WAN_0 <<< "$(echo "$out" | sed -n 2p)"

  # E06b (extra): retomada real de sessao TLS/QUIC com ticket salvo em arquivo (curl >= 8.12).
  if [ "$HAVE_SESS" = 1 ]; then
    docker exec "$CLI" rm -f /tmp/sess.txt
    docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions /tmp/sess.txt "$URL" >/dev/null 2>&1
    out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions /tmp/sess.txt --tls-earlydata -w "$FMT" "$URL" 2>/dev/null) \
      || out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions /tmp/sess.txt -w "$FMT" "$URL" 2>/dev/null) || out=""
    [ -n "$out" ] && record_b E06b "$rep" "HTTP/3 Retomada (ticket TLS)" WAN_0 <<< "$out"
  fi
  log "  Bloco B rep$rep concluida"
}

blocoB_wan_sem_perda() {   # E04, E05, E06
  apply_scenario wan_noloss
  # aquecimento descartado (ARP, cache do Caddy)
  docker exec "$CLI" curl -k -s --http2 -o /dev/null "$URL" >/dev/null 2>&1
  docker exec "$CLI" curl -k -s --http3-only -o /dev/null "$URL" >/dev/null 2>&1
  for r in $(seq 1 "$REPS"); do run_blocoB_rep "$r"; done
}
