record_b() {
  local id="$1" rep="$2" modo="$3" cen="$4" http="$5" ed="${6:-0}" line
  read -r line
  if ! awk -v l="$line" -v h="$http" -v ed="$ed" 'BEGIN{n=split(l,a," ");
        exit !(n>=4 && a[1]==h && a[4]+0>0 && (ed==0 || a[5]+0>0))}'; then
    echo "$id,rep$rep,saida_invalida:'$line'" >> "$FAIL_LOG"
    log "  FALHA: $id rep$rep sem medicao valida (saida: '$line')"
    return 1
  fi
  awk -v id="$id" -v rep="$rep" -v m="$modo" -v s="$cen" -v l="$line" \
    'BEGIN{split(l,a," "); printf "%s,%s,%s,%s,%s,%.3f,%.3f,%.3f,%d\n", id,rep,m,s,a[1],a[2]*1000,a[3]*1000,a[4]*1000,a[5]+0}' >> "$B_CSV"
}

run_blocoB_rep() {   
  local rep="$1" out

  out=$(docker exec "$CLI" curl -k -s --http2 -o /dev/null -w "$FMT" "$URL")
  record_b E04 "$rep" "HTTP/2 (TCP+TLS)" WAN_0 2 <<< "$out"

  out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null -w "$FMT" "$URL")
  record_b E05 "$rep" "HTTP/3 Cold (1-RTT)" WAN_0 3 <<< "$out"

  out=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null -o /dev/null -w "$FMT" "$URL" "$URL")
  record_b E06a_primeira "$rep" "HTTP/3 (1a req. da sessao)" WAN_0 3 <<< "$(sed -n 1p <<< "$out")"
  record_b E06a "$rep" "HTTP/3 reuso de conexao" WAN_0 3 <<< "$(sed -n 2p <<< "$out")"

  if [ "$HAVE_TICKET" = 1 ]; then
    obter_ticket
    out=$(docker exec "$CLI" curl -k -sS -v --http3-only -o /dev/null --ssl-sessions "$SESS_FILE" \
          -w "$FMT" "$URL" 2> "$OUT/logs/E06b_rep$rep.log")
    record_b E06b "$rep" "HTTP/3 retomada (ticket TLS)" WAN_0 3 <<< "$out"
  fi

  if [ "$HAVE_0RTT" = 1 ]; then
    obter_ticket
    out=$(docker exec "$CLI" curl -k -sS -v --http3-only -o /dev/null --tls-earlydata --ssl-sessions "$SESS_FILE" \
          -w "$FMT_ED" "$URL" 2> "$OUT/logs/E06c_rep$rep.log")
    record_b E06c "$rep" "HTTP/3 0-RTT (ticket + early data)" WAN_0 3 1 <<< "$out"
  fi
  log "  Bloco B rep$rep concluida"
}

blocoB_wan_sem_perda() {   
  apply_scenario wan_noloss
  docker exec "$CLI" curl -k -s --http2 -o /dev/null "$URL" >/dev/null 2>&1
  docker exec "$CLI" curl -k -s --http3-only -o /dev/null "$URL" >/dev/null 2>&1
  for r in $(seq 1 "$REPS"); do run_blocoB_rep "$r"; done
}