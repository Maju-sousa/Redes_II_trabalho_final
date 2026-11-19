# Preparacao do ambiente: certificado, objeto de 1 KB, conteineres e dependencias

prepare_files() {
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

setup() {
  $DC up -d || { echo "Falha no docker compose up"; exit 1; }
  sleep 3
  log "Instalando iperf3 e tc no cliente (apk)"
  docker exec -u root "$CLI" sh -c 'apk add --no-cache iperf3 iproute2-tc >/dev/null' \
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
  docker exec "$CLI" curl --help all 2>/dev/null | grep -q -- '--ssl-sessions' && HAVE_SESS=1
  {
    echo "data: $(date -Is)"; echo "kernel host: $(uname -r)"
    echo "cc disponiveis: $avail"; echo "iperf3: $(docker exec "$CLI" iperf3 -v | head -1)"
    echo "curl:"; docker exec "$CLI" curl -V
  } > "$OUT/ambiente.txt"
}
