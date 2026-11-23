#!/usr/bin/env python3
"""Valida a execucao ANTES de gerar graficos/tabelas. Sai com codigo 1 se algo estiver invalido.
Uso (raiz do projeto): python3 analysis/validar.py --reps 5 [--duracao 15] [--permitir-sem-0rtt]"""
import argparse, csv, json, os, re, statistics as st, sys
from collections import defaultdict

RES = "results"
ALGO = {"E01": "cubic", "E02": "cubic", "E03": "bbr"}
HTTP = {"E04": "2", "E05": "3", "E06a": "3", "E06b": "3", "E06c": "3"}
OBRIG_B = ["E04", "E05", "E06a"]
RTT_FAIXA = {"lan": (0.0, 5.0), "wan_loss": (45.0, 60.0), "wan_noloss": (45.0, 60.0)}  # ms (ping medio)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--duracao", type=float, default=15)
    ap.add_argument("--permitir-sem-0rtt", action="store_true")
    a = ap.parse_args()
    erros, avisos = [], []

    def ler(p):
        with open(p, newline="") as f:
            return list(csv.DictReader(f))

    # 0) falhas registradas pelos scripts
    fl = f"{RES}/falhas.log"
    if os.path.exists(fl) and os.path.getsize(fl) > 0:
        erros.append("falhas.log nao esta vazio:\n    " + open(fl).read().strip().replace("\n", "\n    "))

    # 1) Bloco A: amostras, algoritmo e JSON de cada repeticao
    A = defaultdict(list)
    for r in ler(f"{RES}/raw_blocoA.csv"):
        A[r["id"]].append(r)
    for i, alg in ALGO.items():
        rows = A.get(i, [])
        reps = sorted(int(r["rep"]) for r in rows)
        if reps != list(range(1, a.reps + 1)):
            erros.append(f"{i}: repeticoes {reps}, esperado 1..{a.reps}")
        v = [float(r["vazao_mbps"]) for r in rows]
        if any(x <= 0 for x in v):
            erros.append(f"{i}: vazao <= 0 em alguma repeticao")
        if len(v) > 1 and st.mean(v) > 0 and st.stdev(v) / st.mean(v) > 0.30:
            avisos.append(f"{i}: coeficiente de variacao {100*st.stdev(v)/st.mean(v):.0f}% (> 30%): rever outliers")
        for r in rows:
            jf = f"{RES}/json/{i}_rep{r['rep']}.json"
            try:
                j = json.load(open(jf))
            except (OSError, ValueError):
                erros.append(f"{jf}: ausente ou invalido"); continue
            e = j.get("end", {})
            if "error" in j: erros.append(f"{jf}: iperf3 reportou erro: {j['error']}")
            if e.get("sender_tcp_congestion") != alg:
                erros.append(f"{jf}: algoritmo efetivo {e.get('sender_tcp_congestion')!r}, esperado {alg!r}")
            s, rc = e.get("sum_sent", {}), e.get("sum_received", {})
            if abs(s.get("seconds", 0) - a.duracao) > 1.0:
                erros.append(f"{jf}: duracao {s.get('seconds')} s, esperado {a.duracao} s")
            if rc.get("bytes", 0) > s.get("bytes", 0) * 1.001:
                erros.append(f"{jf}: bytes recebidos > enviados")
            if i != "E01":
                rtt = e.get("streams", [{}])[0].get("sender", {}).get("mean_rtt", 0) / 1000
                if not 45 <= rtt <= 65:
                    erros.append(f"{jf}: RTT medio do TCP = {rtt:.1f} ms, fora de 45-65 ms")

    # 2) Bloco B: amostras, versao HTTP, ttfb > 0, prova de 0-RTT
    B = defaultdict(list)
    for r in ler(f"{RES}/raw_blocoB.csv"):
        B[r["id"]].append(r)
    presentes = [i for i in ("E06b", "E06c") if i in B]
    for i in OBRIG_B + presentes:
        rows = B.get(i, [])
        reps = sorted(int(r["rep"]) for r in rows)
        if reps != list(range(1, a.reps + 1)):
            erros.append(f"{i}: repeticoes {reps}, esperado 1..{a.reps}")
        for r in rows:
            if r["http_version"] != HTTP[i]: erros.append(f"{i} rep{r['rep']}: HTTP/{r['http_version']}, esperado HTTP/{HTTP[i]}")
            if float(r["ttfb_ms"]) <= 0: erros.append(f"{i} rep{r['rep']}: TTFB <= 0")
    for r in B.get("E06a", []):
        if float(r["connect_ms"]) != 0.0:
            erros.append(f"E06a rep{r['rep']}: connect_ms={r['connect_ms']} (a 2a requisicao deveria reutilizar a conexao)")
    for r in B.get("E06c", []):
        if int(float(r.get("earlydata_bytes") or 0)) <= 0:
            erros.append(f"E06c rep{r['rep']}: earlydata_bytes = 0, NAO houve 0-RTT")
    if not a.permitir_sem_0rtt and "E06c" not in B:
        erros.append("E06c ausente: 0-RTT nao foi comprovado (use um curl com OpenSSL/ngtcp2 e EarlyData, ou --permitir-sem-0rtt)")
    if "E06b" in B and "E06c" not in B and not a.permitir_sem_0rtt:
        erros.append("E06b existe sem E06c")

    # 3) RTT medido por ping em cada cenario
    try:
        txt = open(f"{RES}/rtt_check.txt", encoding="utf-8").read()
    except OSError:
        txt = ""
        erros.append("rtt_check.txt ausente")
    rtts = {}
    for cen, (lo, hi) in RTT_FAIXA.items():
        m = re.search(rf"== {cen} ==.*?=\s*[\d.]+/([\d.]+)/", txt, re.S)
        if not m: erros.append(f"rtt_check.txt: cenario {cen} sem medicao"); continue
        rtt = rtts[cen] = float(m.group(1))
        if not lo <= rtt <= hi: erros.append(f"RTT do cenario {cen} = {rtt:.1f} ms, fora de {lo}-{hi} ms")

    # 4) 0-RTT ACEITO pelo servidor: enviar early data (tls_earlydata > 0) nao basta; se o servidor rejeita,
    #    o curl refaz com handshake normal e o TTFB volta para ~2 RTT. Exige TTFB medio <= 1,5 x RTT medido.
    if "E06c" in B and "wan_noloss" in rtts:
        t = st.mean(float(r["ttfb_ms"]) for r in B["E06c"])
        if t > 1.5 * rtts["wan_noloss"]:
            erros.append(f"E06c: TTFB medio {t:.1f} ms > 1,5 x RTT ({1.5*rtts['wan_noloss']:.1f} ms): "
                         "early data enviado mas provavelmente REJEITADO pelo servidor (nao e 0-RTT efetivo)")

    for w in avisos: print("AVISO:", w)
    if erros:
        print("EXECUCAO INVALIDA:")
        for e in erros: print(" -", e)
        sys.exit(1)
    print(f"Validacao OK: {len(ALGO)} testes do Bloco A e {len(OBRIG_B)+len(presentes)} modos do Bloco B com {a.reps} amostras validas.")


if __name__ == "__main__":
    main()