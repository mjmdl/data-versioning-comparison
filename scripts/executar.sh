#!/usr/bin/env bash
set -euo pipefail

BANCO=${BANCO:-versionamento}
ESCALAS=${ESCALAS:-"100000 1000000"}
REPETICOES=${REPETICOES:-3}
ESTRATEGIAS=${ESTRATEGIAS:-"base vinterno vexterno"}
LEITURAS=${LEITURAS:-10000}
COMO_POSTGRES=${COMO_POSTGRES:-"sudo -u postgres"}
CONEXAO=${CONEXAO:-}
PASTA=$(cd "$(dirname "$0")" && pwd)
SAIDA=${SAIDA:-$PASTA/resultados/$(date +%Y%m%d-%H%M%S)}

declare -A TABELAS=(
    [base]="base.departamento, base.horario, base.funcionario, base.ferias, base.ponto"
    [vinterno]="vinterno.departamento, vinterno.horario, vinterno.funcionario, vinterno.ferias, vinterno.ponto"
    [vexterno]="vexterno.departamento, vexterno.horario, vexterno.funcionario, vexterno.ferias, vexterno.ponto, vexterno.historia_departamento, vexterno.historia_horario, vexterno.historia_funcionario, vexterno.historia_ferias, vexterno.historia_ponto"
)
declare -A CONSULTAS=([base]=5 [vinterno]=15 [vexterno]=15)

sql() { $COMO_POSTGRES psql $CONEXAO -X -q -v ON_ERROR_STOP=1 -d "$BANCO" "$@"; }
valor() { sql -At -c "$1"; }
executa() { sql -c "$1" > /dev/null; }
bench() {
    local esquema=$1
    shift
    $COMO_POSTGRES env PGOPTIONS="-c search_path=$esquema" pgbench $CONEXAO -n -r -c 1 -M prepared "$@" "$BANCO"
}

importar() {
    local execucao=$1 fase=$2 arquivo=$3 transacoes falhas tps latencia
    transacoes=$(sed -n 's/^number of transactions actually processed: \([0-9]*\).*/\1/p' "$arquivo")
    falhas=$(sed -n 's/^number of failed transactions: \([0-9]*\).*/\1/p' "$arquivo")
    tps=$(sed -n 's/^tps = \([0-9.]*\) .*/\1/p' "$arquivo")
    latencia=$(sed -n 's/^latency average = \([0-9.]*\) ms/\1/p' "$arquivo")
    executa "SELECT resultado.encerrar($execucao, '$fase', ${transacoes:-0}, ${falhas:-0}, ${tps:-0}, ${latencia:-0})"
    awk -v e="$execucao" -v f="$fase" '
        /^statement latencies in milliseconds/ { dentro = 1; next }
        dentro && /^ +[0-9.]+ +[0-9]+ / {
            ordem++
            latencia = $1
            erros = $2
            sub(/^ +[0-9.]+ +[0-9]+ +/, "")
            gsub(/\\/, "\\\\")
            printf "%s\t%s\t%d\t%s\t%s\t%s\n", e, f, ordem, latencia, erros, $0
        }' "$arquivo" | sql -c "\copy resultado.latencia (execucao, fase, ordem, latencia_ms, falhas, comando) FROM STDIN"
}

medir_fase() {
    local execucao=$1 estrategia=$2 fase=$3 arquivo
    shift 3
    arquivo="$SAIDA/$execucao-$fase.txt"
    executa "CHECKPOINT"
    executa "SELECT resultado.iniciar($execucao, '$fase')"
    if ! bench "$estrategia" "$@" > "$arquivo" 2>&1; then
        echo "O pgbench falhou; veja $arquivo"
        exit 1
    fi
    importar "$execucao" "$fase" "$arquivo"
}

if [ "$(valor "SELECT current_setting('autovacuum')")" != off ]; then
    echo "O autovacuum está ligado. Rode configuracao.sql e reinicie o PostgreSQL."
    exit 1
fi
valor "SELECT count(*) FROM public.pg_stat_statements" > /dev/null
for escala in $ESCALAS; do
    if [ "$(valor "SELECT count(*) FROM ensaio.plano WHERE n <= $escala")" != "$escala" ]; then
        echo "O plano não tem $escala operações. Rode CALL ensaio.gerar_plano()."
        exit 1
    fi
    if [ "$(valor "SELECT count(*) FROM ensaio.leitura WHERE escala = $escala")" != $((LEITURAS * 15)) ]; then
        echo "Faltam as leituras da escala $escala. Rode CALL ensaio.gerar_leituras($escala, $LEITURAS)."
        exit 1
    fi
done

mkdir -p "$SAIDA"
echo "Saída do pgbench em $SAIDA"

sql <<SQL
INSERT INTO resultado.ambiente (chave, valor)
SELECT name, current_setting(name) FROM pg_settings
 WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size', 'synchronous_commit', 'fsync',
                'full_page_writes', 'wal_level', 'checkpoint_timeout', 'max_wal_size', 'autovacuum', 'jit')
UNION ALL SELECT 'versao', version()
UNION ALL SELECT 'sistema', '$(uname -srm)'
UNION ALL SELECT 'processadores', '$(nproc)'
UNION ALL SELECT 'memoria', '$(free -h | awk '/^Mem:/ { print $2 }')'
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor;

INSERT INTO resultado.complexidade (estrategia, item, quantidade)
SELECT n.nspname, CASE c.relkind WHEN 'r' THEN 'tabelas' ELSE 'indices' END, count(*)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('base', 'vinterno', 'vexterno') AND c.relkind IN ('r', 'i')
 GROUP BY 1, 2
UNION ALL
SELECT n.nspname, 'funcoes', count(*)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('base', 'vinterno', 'vexterno')
 GROUP BY 1
UNION ALL
SELECT n.nspname, 'gatilhos', count(*)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('base', 'vinterno', 'vexterno') AND NOT t.tgisinternal
 GROUP BY 1
ON CONFLICT (estrategia, item) DO UPDATE SET quantidade = EXCLUDED.quantidade;
SQL
for arquivo in base vinterno vexterno; do
    if [ -f "$PASTA/$arquivo.ddl" ]; then
        executa "INSERT INTO resultado.complexidade VALUES ('$arquivo', 'linhas_ddl', $(wc -l < "$PASTA/$arquivo.ddl"))
                ON CONFLICT (estrategia, item) DO UPDATE SET quantidade = EXCLUDED.quantidade"
    fi
done

for escala in $ESCALAS; do
    for repeticao in $(seq 1 "$REPETICOES"); do
        for estrategia in $ESTRATEGIAS; do
            echo "$(date +%T)  escala $escala, repetição $repeticao, $estrategia"
            executa "DELETE FROM resultado.execucao WHERE escala = $escala AND estrategia = '$estrategia' AND repeticao = $repeticao"
            executa "TRUNCATE ${TABELAS[$estrategia]}"
            execucao=$(valor "INSERT INTO resultado.execucao (escala, estrategia, repeticao) VALUES ($escala, '$estrategia', $repeticao) RETURNING id")
            executa "SELECT resultado.medir($execucao, 'antes', '$estrategia')"
            medir_fase "$execucao" "$estrategia" escrita -D n=0 -t "$escala" -f "$PASTA/escrita.sql"
            executa "SELECT resultado.medir($execucao, 'depois', '$estrategia')"
            executa "VACUUM ANALYZE ${TABELAS[$estrategia]}"
            medir_fase "$execucao" "$estrategia" leitura -D i=0 -D escala="$escala" -t $((LEITURAS * ${CONSULTAS[$estrategia]})) -f "$PASTA/leitura_$estrategia.sql"
            if [ "$estrategia" != base ]; then
                executa "INSERT INTO resultado.consistencia SELECT $execucao, * FROM ensaio.consistencia('$estrategia')"
            fi
        done
        if [[ " $ESTRATEGIAS " == *" base "* && " $ESTRATEGIAS " == *" vinterno "* && " $ESTRATEGIAS " == *" vexterno "* ]]; then
            executa "DELETE FROM resultado.verificacao WHERE escala = $escala AND repeticao = $repeticao"
            sql -At -F $'\t' -f "$PASTA/verificacao.sql" | sed "s/^/$escala\t$repeticao\t/" | sql -c "\copy resultado.verificacao FROM STDIN"
        fi
    done
done

echo "$(date +%T)  fim; rode relatorio.sql"
