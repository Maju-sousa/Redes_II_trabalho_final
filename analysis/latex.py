"""Gera report/tabelas.tex e report/numeros.tex (macros usadas pelo relatorio.tex)."""
from dados import REP, ROT_A, ROT_B, MACRO, fx


def escrever_tabelas(sA, sB):
    with open(f"{REP}/tabelas.tex", "w", encoding="utf-8") as f:
        f.write("\\begin{table}[t]\\centering\\small\n"
                "\\caption{Bloco A: vazão (média $\\pm$ desvio padrão) e retransmissões TCP.}\\label{tab:blocoA}\n"
                "\\begin{tabular}{llrrr}\\toprule\nID & Configuração & Vazão (Mbps) & DP & Retrans. \\\\ \\midrule\n")
        for i, (m, s, rt, n) in sA.items():
            f.write(f"{i} & {ROT_A[i][0]}, {ROT_A[i][1].split(' (')[0]} & {fx(m, 2)} & {fx(s, 2)} & {rt} \\\\\n")
        f.write("\\bottomrule\\end{tabular}\n\\end{table}\n\n")
        f.write("\\begin{table}[t]\\centering\\small\n"
                "\\caption{Bloco B: TTFB em ms (RTT = 50 ms, 0\\% de perda).}\\label{tab:blocoB}\n"
                "\\begin{tabular}{llrrrr}\\toprule\nID & Modo & Média & DP & Mín. & Máx. \\\\ \\midrule\n")
        for i, (m, s, lo, hi, n) in sB.items():
            f.write(f"{i} & {ROT_B[i].replace(chr(10), ' ')} & {fx(m)} & {fx(s)} & {fx(lo)} & {fx(hi)} \\\\\n")
        f.write("\\bottomrule\\end{tabular}\n\\end{table}\n")


def escrever_numeros(sA, sB):
    with open(f"{REP}/numeros.tex", "w", encoding="utf-8") as f:
        for i, (m, s, rt, n) in sA.items():
            k = MACRO[i]
            f.write(f"\\renewcommand{{\\{k}Media}}{{{fx(m, 2)}}}\\renewcommand{{\\{k}DP}}{{{fx(s, 2)}}}"
                    f"\\renewcommand{{\\{k}Ret}}{{{rt}}}\n")
        for i, (m, s, lo, hi, n) in sB.items():
            k = MACRO[i]
            f.write(f"\\renewcommand{{\\{k}Media}}{{{fx(m)}}}\\renewcommand{{\\{k}DP}}{{{fx(s)}}}\n")
        if "E01" in sA and "E02" in sA and sA["E01"][0] > 0:
            f.write(f"\\renewcommand{{\\quedaCubic}}{{{fx(100 * (1 - sA['E02'][0] / sA['E01'][0]))}}}\n")
        if "E02" in sA and "E03" in sA and sA["E02"][0] > 0:
            f.write(f"\\renewcommand{{\\razaoBBR}}{{{fx(sA['E03'][0] / sA['E02'][0])}}}\n")
        if "E04" in sB and "E05" in sB:
            f.write(f"\\renewcommand{{\\difHttpDois}}{{{fx(sB['E04'][0] - sB['E05'][0])}}}\n")
        if "E05" in sB and "E06" in sB:
            f.write(f"\\renewcommand{{\\difCold}}{{{fx(sB['E05'][0] - sB['E06'][0])}}}\n")
        if "E04" in sB and "E06" in sB:
            f.write(f"\\renewcommand{{\\difTotal}}{{{fx(sB['E04'][0] - sB['E06'][0])}}}\n")
