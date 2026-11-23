
prepare_files() {
  rm -rf "$OUT/json" "$OUT/logs"; rm -f "$OUT/tc_stats.txt" "$FAIL_LOG"   # nao misturar saidas de execucoes antigas
  mkdir -p certs site "$OUT/json" "$OUT/logs" figures report
  [ -f site/obj1k.bin ] || head -c 1024 /dev/urandom > site/obj1k.bin   # objeto de 1 KB
  if [ ! -f certs/server.crt ]; then
    log "Gerando certificado autoassinado (SAN IP:${IP_H3})"
    local ARGS=(req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30
                -subj "/CN=${IP_H3}" -addext "subjectAltName=IP:${IP_H3}")
    if command -v openssl >/dev/null 2>&1; then
      openssl "${ARGS[@]}" -keyout certs/server.key -out certs/server.crt 2>/dev/null
    else
      docker run --rm -v "$PWD/certs:/certs" alpine/openssl "${ARGS[@]}" \
        -keyout /certs/server.key -out /certs/server.crt 2>/dev/null
    fi
  fi
  chmod 644 certs/* site/*
}

instalar_pacotes() {
  docker exec -u root "$1" sh -c "
    if command -v apk >/dev/null 2>&1; then apk add --no-cache $2 >/dev/null
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $3 >/dev/null 2>&1
    else exit 1; fi"
}

aguardar_caddy() {
  for _ in $(seq 1 30); do
    docker exec "$CLI" curl -k -s --http2 -o /dev/null "$URL" && return 0
    sleep 1
  done
  echo "Caddy nao respondeu em $URL"; exit 1
}

# Conexao QUIC completa que grava o ticket TLS em $SESS_FILE (o ticket de 0-RTT e de uso unico:
# por isso um ticket novo e obtido imediatamente antes de CADA medicao de E06b/E06c).
obter_ticket() {
  docker exec "$CLI" rm -f "$SESS_FILE"
  docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions "$SESS_FILE" "$URL" >/dev/null 2>&1
}

# Decide UMA vez o que o curl do cliente consegue medir (evita misturar variantes entre repeticoes):
#   HAVE_TICKET=1 -> E06b (conexao nova + ticket TLS, sem early data)
#   HAVE_0RTT=1   -> E06c (conexao nova + ticket + early data; a prova e tls_earlydata > 0)
detectar_retomada() {
  HAVE_TICKET=0; HAVE_0RTT=0
  local ajuda   # nao usar 'curl --help | grep -q' com pipefail: grep sai cedo, curl recebe SIGPIPE e o teste da falso negativo
  ajuda=$(docker exec "$CLI" curl --help all 2>/dev/null)
  if ! grep -q -- '--ssl-sessions' <<< "$ajuda"; then
    log "curl do cliente sem --ssl-sessions: so E06a (reuso de conexao); 0-RTT NAO sera medido"; return
  fi
  obter_ticket
  if ! docker exec "$CLI" test -s "$SESS_FILE"; then
    log "ticket TLS nao foi gravado: so E06a; 0-RTT NAO sera medido"; return
  fi
  HAVE_TICKET=1
  if [ "${PULAR_0RTT:-0}" = 1 ]; then
    log "E06c pulado (PULAR_0RTT=1)"
  elif grep -q -- '--tls-earlydata' <<< "$ajuda"; then
    obter_ticket
    local ed
    ed=$(docker exec "$CLI" curl -k -s --http3-only -o /dev/null --tls-earlydata \
         --ssl-sessions "$SESS_FILE" -w '%{tls_earlydata}' "$URL" 2>/dev/null)
    [ "${ed:-0}" -gt 0 ] 2>/dev/null && HAVE_0RTT=1
  fi
  log "E06b (ticket TLS): $HAVE_TICKET | E06c (0-RTT, early data enviado): $HAVE_0RTT"
  [ "$HAVE_0RTT" = 1 ] || log "AVISO: 0-RTT nao comprovado (sem EarlyData no curl ou tls_earlydata = 0)"
}

setup() {
  $DC up -d --build || { echo "Falha no docker compose up"; exit 1; }
  sleep 3
  log "Instalando iperf3 e tc no cliente (se ja existirem, nada muda)"
  instalar_pacotes "$CLI" "iperf3 iproute2-tc" "iperf3 iproute2" \
    || { echo "Falha ao instalar pacotes no cliente (rede/DNS do Docker?)"; exit 1; }
  for c in "$SRV_TCP" "$SRV_H3"; do
    docker exec -u root "$c" sh -c 'command -v tc >/dev/null 2>&1 || apk add --no-cache iproute2-tc >/dev/null 2>&1 || (apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq iproute2 >/dev/null 2>&1)'
    docker exec "$c" tc -V >/dev/null 2>&1 || { echo "tc indisponivel em $c"; exit 1; }
  done
  local avail
  avail=$(docker exec "$CLI" cat /proc/sys/net/ipv4/tcp_available_congestion_control)
  case " $avail " in
    *" bbr "*) ;;
    *) echo "BBR indisponivel no kernel do host (disponiveis: $avail). Rode: sudo modprobe tcp_bbr"; exit 1;;
  esac
  local ver; ver=$(docker exec "$CLI" curl -V)
  grep -qi 'HTTP3' <<< "$ver" \
    || { echo "O curl do cliente nao tem suporte a HTTP/3"; exit 1; }
  grep -qw 'HTTP2' <<< "$ver" \
    || { echo "O curl do cliente nao tem suporte a HTTP/2 (E04 usa --http2)"; exit 1; }
  [ "$(docker exec "$CLI" cat /proc/sys/net/ipv4/tcp_no_metrics_save)" = 1 ] \
    || { echo "tcp_no_metrics_save nao esta ativo no cliente (verifique 'sysctls' no docker-compose.yml)"; exit 1; }
  tc_clear                 # garante ambiente sem netem antes de sondar o servidor
  aguardar_caddy
  detectar_retomada
  {
    echo "data: $(date -Is)"
    echo "codigo (git): $(git rev-parse --short HEAD 2>/dev/null || echo n/a)  alteracoes nao commitadas no codigo: $(git status --porcelain -- run_n3.sh scripts analysis client docker-compose.yml Caddyfile 2>/dev/null | wc -l)"
    echo "kernel host: $(uname -r)"; echo "docker: $(docker --version)"
    echo "imagem cliente: $(docker inspect -f '{{.Config.Image}}' "$CLI" 2>/dev/null)"
    echo "cc disponiveis: $avail"; echo "iperf3: $(docker exec "$CLI" iperf3 -v | head -1)"
    echo "tcp_no_metrics_save (cliente): $(docker exec "$CLI" cat /proc/sys/net/ipv4/tcp_no_metrics_save)"
    echo "E06b (ticket TLS): $HAVE_TICKET | E06c (0-RTT, early data): $HAVE_0RTT"
    echo "curl:"; docker exec "$CLI" curl -V
  } > "$OUT/ambiente.txt"
}
