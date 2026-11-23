import csv
import json
import re
import statistics as st
from collections import defaultdict

RES, FIG, REP = "results", "figures", "report"

ROT_A = {"E01": ("TCP CUBIC", "LAN (RTT 1 ms, 0% perda)"),
         "E02": ("TCP CUBIC", "WAN (RTT 50 ms, 2% perda)"),
         "E03": ("TCP BBR", "WAN (RTT 50 ms, 2% perda)")}
ROT_B = {"E04": "HTTP/2\n(TCP+TLS)",
         "E05": "HTTP/3 Cold\n(1-RTT)",
         "E06a": "HTTP/3\nreuso de conexão",
         "E06b": "HTTP/3 retomada\n(ticket TLS)",
         "E06c": "HTTP/3 0-RTT\n(ticket + early data)"}
MACRO = {"E01": "Eum", "E02": "Edois", "E03": "Etres", "E04": "Equatro", "E05": "Ecinco",
         "E06a": "Eseisa", "E06b": "Eseisb", "E06c": "Eseisc"}
IDS_B = ["E04", "E05", "E06a", "E06b", "E06c"]


def rtt_medio(cenario, padrao=50.0):
    """RTT medio (ms) medido por ping em results/rtt_check.txt para o cenario dado (ex.: 'wan_noloss')."""
    try:
        with open(f"{RES}/rtt_check.txt", encoding="utf-8") as f:
            txt = f.read()
    except OSError:
        return padrao
    m = re.search(rf"== {cenario} ==.*?=\s*[\d.]+/([\d.]+)/", txt, re.S)
    return float(m.group(1)) if m else padrao


def ler_csv(caminho):
    with open(caminho, newline="") as f:
        return list(csv.DictReader(f))


def media_dp(v):
    return st.mean(v), (st.stdev(v) if len(v) > 1 else 0.0)


def fx(x, d=1):
    """Formata numero com virgula decimal (padrao do relatorio em portugues)."""
    return f"{x:.{d}f}".replace(".", ",")


def resumo_bloco_a():
    """Retorna {id: (media, dp, retransmissoes_total, n)} para E01..E03."""
    d = defaultdict(lambda: {"v": [], "r": []})
    for r in ler_csv(f"{RES}/raw_blocoA.csv"):
        d[r["id"]]["v"].append(float(r["vazao_mbps"]))
        d[r["id"]]["r"].append(int(r["retransmissoes"]))
    return {i: (*media_dp(d[i]["v"]), sum(d[i]["r"]), len(d[i]["v"]))
            for i in ["E01", "E02", "E03"] if i in d}


def retrans_pct():
    """{id: % de segmentos retransmitidos} = retransmits / (bytes enviados / MSS), lido dos JSON do iperf3.
    A contagem absoluta de retransmissoes nao e comparavel entre CUBIC e BBR: o BBR envia muito mais segmentos."""
    acc = defaultdict(lambda: [0, 0.0])
    for r in ler_csv(f"{RES}/raw_blocoA.csv"):
        with open(f"{RES}/json/{r['id']}_rep{r['rep']}.json") as f:
            j = json.load(f)
        s = j["end"]["sum_sent"]
        acc[r["id"]][0] += s["retransmits"]
        acc[r["id"]][1] += s["bytes"] / j["start"]["tcp_mss_default"]
    return {i: 100 * a / b for i, (a, b) in acc.items() if b > 0}


def resumo_bloco_b():
    """Retorna {id: (media, dp, min, max, n)} para E04, E05 e as variantes de E06 presentes (a, b, c)."""
    d = defaultdict(list)
    for r in ler_csv(f"{RES}/raw_blocoB.csv"):
        d[r["id"]].append(float(r["ttfb_ms"]))
    return {i: (*media_dp(d[i]), min(d[i]), max(d[i]), len(d[i])) for i in IDS_B if i in d}


def salvar_resumos(sA, sB):
    pct = retrans_pct()
    with open(f"{RES}/resumo_blocoA.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "algoritmo", "cenario", "n", "vazao_media_mbps", "vazao_dp_mbps",
                    "retransmissoes_total", "retransmissoes_pct_segmentos"])
        for i, (m, s, rt, n) in sA.items():
            w.writerow([i, *ROT_A[i], n, round(m, 3), round(s, 3), rt, round(pct.get(i, 0.0), 3)])
    with open(f"{RES}/resumo_blocoB.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "modo", "n", "ttfb_medio_ms", "ttfb_dp_ms", "min_ms", "max_ms"])
        for i, (m, s, lo, hi, n) in sB.items():
            w.writerow([i, ROT_B[i].replace("\n", " "), n, round(m, 3), round(s, 3), round(lo, 3), round(hi, 3)])