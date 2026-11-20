#!/usr/bin/env python3
"""Ponto de entrada da analise. Execute a partir da raiz do projeto:  python3 analysis/analyze.py"""
import os
from dados import FIG, REP, resumo_bloco_a, resumo_bloco_b, salvar_resumos, rtt_medio
from graficos import grafico_vazao, grafico_ttfb
from latex import escrever_tabelas, escrever_numeros


def main():
    os.makedirs(FIG, exist_ok=True)
    os.makedirs(REP, exist_ok=True)
    sA, sB = resumo_bloco_a(), resumo_bloco_b()
    salvar_resumos(sA, sB)
    grafico_vazao(sA)
    grafico_ttfb(sB, rtt_medio("wan_noloss"))
    escrever_tabelas(sA, sB)
    escrever_numeros(sA, sB)
    print("Bloco A:", {i: (round(v[0], 2), round(v[1], 2), v[2]) for i, v in sA.items()})
    print("Bloco B:", {i: (round(v[0], 1), round(v[1], 1)) for i, v in sB.items()})


if __name__ == "__main__":
    main()