# TP3 (N3) Redes de Computadores II - UFPI/CSHNB
Análise experimental de CUBIC vs. BBR e HTTP/2 vs. HTTP/3 (cold / retomada / 0-RTT) com Docker e `tc netem`.

Autores: Nome Aluno 1, Nome Aluno 2 | Vídeo: https://youtu.be/XXXXXXXXXXX

## Requisitos (máquina Linux, ou WSL2 com kernel que tenha BBR)
Docker + Docker Compose, Python 3 com `matplotlib` (`pip install -r requirements.txt`), `openssl` (ou Docker, para gerar o certificado).
Módulo BBR no host: `sudo modprobe tcp_bbr`.
A imagem do cliente (`client/Dockerfile`) é construída na primeira execução (compila OpenSSL 3.5, ngtcp2, nghttp3 e curl: leva alguns minutos).
Confira: `docker run --rm --entrypoint curl tp3-client -V | grep -E "HTTP3|EarlyData"` deve listar as duas palavras.

## Uso
```bash
REPS=1 DURATION=5 ./run_n3.sh   # teste rápido de ambiente
./run_n3.sh                     # execução completa (testes x 5 repetições)
```
Variáveis: `REPS` (5), `DURATION` (15 s), `MIRROR_CLIENT` (1), `KEEP_UP` (0), `PERMITIR_SEM_0RTT` (0).
O script **valida** a execução (`analysis/validar.py`) antes de gerar gráficos e tabelas e termina com código 1 se algo estiver incompleto ou inválido (repetição faltando, medição inválida, RTT fora da faixa, 0-RTT não comprovado).
Ao final: dados brutos em `results/`, gráficos em `figures/`, tabelas e macros LaTeX em `report/`.

## Estrutura
```
docker-compose.yml   3 contêineres (iperf3 .10, Caddy HTTP/3 .30, cliente .50), NET_ADMIN
client/Dockerfile    cliente: curl (OpenSSL 3.5 + ngtcp2 + nghttp3), iperf3, tc
Caddyfile            HTTP/1.1, HTTP/2 e HTTP/3 com certificado autoassinado (0-RTT é habilitado por padrão no Caddy)
run_n3.sh            orquestrador (netem, testes, validação, análise, limpeza)
scripts/config.sh    variáveis e log
scripts/ambiente.sh  certificado, objeto de 1 KB, subida dos contêineres, dependências, detecção de ticket/0-RTT
scripts/netem.sh     tc netem por cenário (LAN, WAN com perda, WAN sem perda), verificação da regra, contadores tc, limpeza
scripts/bloco_a.sh   E01-E03: iperf3 (CUBIC/BBR)
scripts/bloco_b.sh   E04, E05 e E06a/E06b/E06c: curl, TTFB
analysis/            dados.py (CSV e estatística), graficos.py, latex.py, analyze.py, validar.py
report/              saída do analyze.py (tabelas.tex, numeros.tex), criada na execução
results/             raw_blocoA.csv, raw_blocoB.csv, json/ (iperf3), logs/ (curl -v), tc_stats.txt, rtt_check.txt, ambiente.txt
```

## Os três modos de "warm" (E06)
| ID | O que é | Prova | TTFB esperado |
|---|---|---|---|
| E06a | Reuso de conexão QUIC já aberta (2ª requisição do mesmo `curl`) | `connect_ms = 0` | ~1 RTT |
| E06b | Conexão **nova** com ticket TLS salvo (`--ssl-sessions`), sem early data | log `-v` em `results/logs/` | ~2 RTT (a retomada não economiza RTT sem early data) |
| E06c | Conexão **nova** com ticket + **0-RTT** (`--tls-earlydata`) | `earlydata_bytes > 0` (`%{tls_earlydata}`) | ~1 RTT |

Reuso de conexão, retomada de sessão e envio de dados 0-RTT são mecanismos diferentes. O "Warm/Resumed" do enunciado corresponde ao E06c.
O ticket é obtido imediatamente antes de cada medição de E06b/E06c (tickets de 0-RTT são de uso único).

## Validação e reprodutibilidade
- `tc qdisc show` confere, em cada contêiner, o atraso (e a perda de 2% só no WAN com perda) logo após aplicar o `netem`; o RTT é medido por `ping` (10 pacotes) em `results/rtt_check.txt`.
- `validar.py` exige as N repetições de cada teste, algoritmo efetivo (campo `sender_tcp_congestion` do JSON), duração, RTT TCP médio de 45-65 ms nos testes WAN, versão HTTP esperada, TTFB > 0 e early data > 0 no E06c.
- `results/tc_stats.txt` guarda os contadores do `tc` antes/depois de cada fluxo (perda efetiva e transbordo da fila do `netem`).
- `net.ipv4.tcp_no_metrics_save=1` no cliente evita que o `ssthresh` de uma repetição afete a seguinte.
- Vazão = `sum_received` do iperf3; retransmissões = `sum_sent.retransmits`; a tabela traz também a taxa por segmento enviado, porque o BBR envia muito mais segmentos que o CUBIC e a contagem absoluta não é comparável.

## Decisões de projeto e desvios em relação ao enunciado
| Item | Enunciado | Este projeto | Motivo |
|---|---|---|---|
| Imagem do cliente | `curlimages/curl:latest` | `client/Dockerfile` (`tp3-client`) | o curl da imagem original não tinha HTTP/3; o curl com BoringSSL/quiche não suporta `--tls-earlydata` |
| `Caddyfile` | só `certs` e `site` montados | `Caddyfile` montado também | o Caddy precisa dele para servir HTTPS/HTTP/3 com o certificado de teste |
| `netem` | só nos servidores | também no cliente (`MIRROR_CLIENT=1`) | `netem` age só na saída; sem isso o RTT seria metade e os dados do cliente não sofreriam atraso nem perda |
| E06 | "Warm / Resumption" | E06a (reuso), E06b (ticket) e E06c (0-RTT) | distinguir reuso de conexão, retomada de sessão e 0-RTT efetivo |
| `sysctls` | ausente | `tcp_no_metrics_save=1` no cliente | amostras independentes |
| `version: '3.8'` | presente | mantido | obsoleto, só gera aviso |

`results/ambiente.txt` registra o commit do código, as versões, o curl e se E06b/E06c foram habilitados.