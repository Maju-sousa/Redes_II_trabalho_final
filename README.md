# TP3 (N3) Redes de Computadores II - UFPI/CSHNB
Análise experimental de CUBIC vs. BBR e HTTP/2 vs. HTTP/3 (cold / warm) com Docker e `tc netem`.

Autores: Nome Aluno 1, Nome Aluno 2 | Vídeo: https://youtu.be/XXXXXXXXXXX

## Requisitos (máquina Linux, ou WSL2 com kernel que tenha BBR)
Docker + Docker Compose, Python 3 com `matplotlib` (`pip install -r requirements.txt`), `openssl` (ou Docker, para gerar o certificado).
Módulo BBR no host: `sudo modprobe tcp_bbr`. O `curl` do cliente precisa listar `HTTP3` em `curl -V`.

## Uso
```bash
REPS=1 DURATION=5 ./run_n3.sh   # teste rápido de ambiente
./run_n3.sh                     # execução completa (6 testes x 5 repetições)
```
Variáveis: `REPS` (5), `DURATION` (15 s), `MIRROR_CLIENT` (1), `KEEP_UP` (0).
Ao final: dados brutos em `results/`, gráficos em `figures/`, tabelas e macros LaTeX em `report/` (o relatório em si ainda não está incluído).

## Estrutura
```
docker-compose.yml   3 contêineres (iperf3 .10, Caddy HTTP/3 .30, cliente curl .50), NET_ADMIN
Caddyfile            HTTP/1.1, HTTP/2 e HTTP/3 com certificado autoassinado
run_n3.sh            orquestrador
scripts/config.sh    variáveis e log
scripts/ambiente.sh  certificado, objeto de 1 KB, subida dos contêineres, dependências
scripts/netem.sh     tc netem por cenário (LAN, WAN com perda, WAN sem perda) e limpeza
scripts/bloco_a.sh   E01-E03: iperf3 (CUBIC/BBR)
scripts/bloco_b.sh   E04-E06 (+E06b extra): curl, TTFB
analysis/            dados.py (CSV e estatística), graficos.py, latex.py, analyze.py
report/              saída do analyze.py (tabelas.tex, numeros.tex), criada na execução
```

## Decisão de projeto: RTT
O `netem` atua só na saída da interface. Aplicado só nos servidores, o RTT seria metade do desejado.
Por isso a regra é espelhada no cliente (`MIRROR_CLIENT=1`); o RTT efetivo fica em `results/rtt_check.txt`.

## Desvios em relação ao enunciado (e por quê)
| Item | Enunciado | Este projeto | Motivo |
|---|---|---|---|
| Imagem do cliente | `curlimages/curl:latest` | `alpine/curl-http3:latest` (troca: `CLIENT_IMAGE=...`) | o curl da imagem original não tinha HTTP/3 |
| `Caddyfile` | só `certs` e `site` montados | `Caddyfile` montado também | o Caddy precisa dele para servir HTTPS/HTTP/3 com o certificado de teste |
| `netem` | só nos servidores | também no cliente (`MIRROR_CLIENT=1`) | `netem` age só na saída; sem isso o RTT seria metade e os dados do cliente não sofreriam a perda |
| E06 | "Warm / Resumption" | E06 = duas requisições na mesma chamada do `curl` (reuso de conexão); E06b = retomada por ticket, se o `curl` suportar `--ssl-sessions` | o enunciado permite "requisições sequenciais na mesma chamada do curl"; o TTFB esperado é ≈ 1 RTT, igual ao do 0-RTT |
| `version: '3.8'` | presente | mantido | obsoleto, só gera aviso |

`results/ambiente.txt` registra o commit do código, as versões e se o E06b foi habilitado.