# Preparacao do ambiente: certificado, objeto de 1 KB, conteineres e dependencias

prepare_files() {
  rm -rf "$OUT/json"                       # nao misturar JSONs de execucoes antigas
  mkdir -p certs site "$OUT/json" figures report
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

# instalar_pacotes <conteiner> "<pacotes apk>" "<pacotes apt>"   (cliente Alpine ou Debian/Ubuntu)
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

# Decide UMA vez qual variante de retomada o curl suporta (evita misturar variantes entre repeticoes).
detectar_retomada() {
  HAVE_SESS=0; SESS_FLAGS=""; SESS_ROTULO=""
  if ! docker exec "$CLI" curl --help all 2>/dev/null | grep -q -- '--ssl-sessions'; then
    log "curl do cliente sem --ssl-sessions: E06b omitido (E06 = reuso de conexao, permitido pelo enunciado)"
    return
  fi
  local variante
  for variante in "--tls-earlydata" ""; do
    docker exec "$CLI" rm -f "$SESS_FILE"
    docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions "$SESS_FILE" "$URL" >/dev/null 2>&1 || continue
    if docker exec "$CLI" curl -k -s --http3-only -o /dev/null --ssl-sessions "$SESS_FILE" $variante "$URL" >/dev/null 2>&1; then
      HAVE_SESS=1
      SESS_FLAGS="--ssl-sessions $SESS_FILE $variante"
      if [ -n "$variante" ]; then SESS_ROTULO="HTTP/3 Retomada (ticket + early data)"
      else SESS_ROTULO="HTTP/3 Retomada (ticket, sem early data)"; fi
      log "E06b habilitado: $SESS_ROTULO"
      return
    fi
  done
  log "curl aceita --ssl-sessions mas a retomada falhou: E06b omitido"
}

setup() {
  $DC up -d || { echo "Falha no docker compose up"; exit 1; }
  sleep 3
  log "Instalando iperf3 e tc no cliente"
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
  docker exec "$CLI" curl -V | grep -qi 'HTTP3' \
    || { echo "O curl do cliente nao tem suporte a HTTP/3"; exit 1; }
  tc_clear                 # garante ambiente sem netem antes de sondar o servidor
  aguardar_caddy
  detectar_retomada
  {
    echo "data: $(date -Is)"
    echo "codigo (git): $(git rev-parse --short HEAD 2>/dev/null || echo n/a)  alteracoes nao commitadas no codigo: $(git status --porcelain -- run_n3.sh scripts analysis docker-compose.yml Caddyfile 2>/dev/null | wc -l)"
    echo "kernel host: $(uname -r)"; echo "docker: $(docker --version)"
    echo "imagem cliente: $(docker inspect -f '{{.Config.Image}}' "$CLI" 2>/dev/null)"
    echo "cc disponiveis: $avail"; echo "iperf3: $(docker exec "$CLI" iperf3 -v | head -1)"
    echo "E06b: ${SESS_ROTULO:-omitido}"
    echo "curl:"; docker exec "$CLI" curl -V
  } > "$OUT/ambiente.txt"
}