import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from dados import FIG, ROT_A, ROT_B, fx


def _salvar(fig, nome):
    fig.tight_layout()
    fig.savefig(f"{FIG}/{nome}.pdf")
    fig.savefig(f"{FIG}/{nome}.png", dpi=200)
    plt.close(fig)


def grafico_vazao(sA):
    ids = list(sA)
    means = [sA[i][0] for i in ids]
    sds = [sA[i][1] for i in ids]
    fig, ax = plt.subplots(figsize=(6.2, 4.0))
    ax.bar(range(len(ids)), means, yerr=sds, capsize=6,
           color=["#4C72B0", "#C44E52", "#55A868"][:len(ids)], edgecolor="black", linewidth=0.6)
    for k, (m, s) in enumerate(zip(means, sds)):
        ax.annotate(fx(m), (k, m + s), xytext=(0, 4), textcoords="offset points", ha="center", fontsize=9)
    ax.set_xticks(range(len(ids)))
    ax.set_xticklabels([f"{i}\n{ROT_A[i][0]}\n{ROT_A[i][1]}" for i in ids], fontsize=8)
    pos = [m for m in means if m > 0]
    usar_log = bool(pos) and max(pos) / min(pos) > 50   # LAN e WAN diferem em ordens de grandeza
    if usar_log:
        ax.set_yscale("log")
        ax.set_ylim(top=max(m + s for m, s in zip(means, sds)) * 3)   # folga para o rotulo da barra mais alta
    ax.set_ylabel("Vazão média (Mbps)" + (" - escala log" if usar_log else ""))
    ax.set_xlabel("Experimento (algoritmo / cenário de rede)")
    ax.set_title(f"Vazão TCP em fluxo de 15 s (média ± desvio padrão, n = {sA[ids[0]][3]})", fontsize=10)
    ax.grid(axis="y", alpha=0.3)
    _salvar(fig, "grafico1_vazao")


def grafico_ttfb(sB, rtt_ms=50.0):
    ids = list(sB)
    means = [sB[i][0] for i in ids]
    sds = [sB[i][1] for i in ids]
    fig, ax = plt.subplots(figsize=(7.6, 4.2))
    ax.bar(range(len(ids)), means, yerr=sds, capsize=6,
           color=["#C44E52", "#4C72B0", "#55A868", "#8172B2", "#CCB974"][:len(ids)],
           edgecolor="black", linewidth=0.6)
    for k, (m, s) in enumerate(zip(means, sds)):
        ax.annotate(fx(m), (k, m + s), xytext=(0, 4), textcoords="offset points", ha="center", fontsize=9)
    for k in (1, 2, 3):   # referencias teoricas: k x RTT medido (ping)
        ax.axhline(rtt_ms * k, ls=":", lw=0.9, color="gray", label=f"{k}×RTT nominal ({rtt_ms * k:.0f} ms)")
    ax.set_ylim(0, max(m + s for m, s in zip(means, sds)) * 1.25)
    ax.legend(loc="upper right", fontsize=7, frameon=True)
    ax.set_xticks(range(len(ids)))
    ax.set_xticklabels([f"{i}\n{ROT_B[i]}" for i in ids], fontsize=7.5)
    ax.set_ylabel("TTFB médio - time_starttransfer (ms)")
    ax.set_xlabel("Modo de conexão (WAN, RTT nominal 50 ms, 0% perda)")
    ax.set_title(f"Tempo até o primeiro byte, objeto de 1 KB (média ± DP, n = {sB[ids[0]][4]})", fontsize=10)
    ax.grid(axis="y", alpha=0.3)
    _salvar(fig, "grafico2_ttfb")