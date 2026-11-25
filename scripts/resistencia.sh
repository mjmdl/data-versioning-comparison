#!/usr/bin/env bash
set -euo pipefail

BANCO=${BANCO:-versionamento}
ESCALA=${ESCALA:-100000}
ESTRATEGIAS=${ESTRATEGIAS:-"vinterno vexterno"}
PARAR=${PARAR:-"systemctl kill --signal=SIGKILL postgresql@17-main"}
INICIAR=${INICIAR:-"systemctl start postgresql@17-main"}
ESPERA=${ESPERA:-10}
CLIENTES=${CLIENTES:-8}
DURACAO=${DURACAO:-30}
COMO_POSTGRES=${COMO_POSTGRES:-"sudo -u postgres"}
CONEXAO=${CONEXAO:-}
PASTA=$(cd "$(dirname "$0")" && pwd)

declare -A TABELAS=(
    [vinterno]="vinterno.departamento, vinterno.horario, vinterno.funcionario, vinterno.ferias, vinterno.ponto"
    [vexterno]="vexterno.departamento, vexterno.horario, vexterno.funcionario, vexterno.ferias, vexterno.ponto, vexterno.historia_departamento, vexterno.historia_horario, vexterno.historia_funcionario, vexterno.historia_ferias, vexterno.historia_ponto"
)
declare -A VERSOES=(
    [vinterno]="(SELECT count(*) FROM vinterno.funcionario WHERE valido_desde >= '2040-01-01') + (SELECT count(*) FROM vinterno.ponto WHERE data_inclusao >= '2040-01-01')"
    [vexterno]="(SELECT count(*) FROM vexterno.historia_funcionario WHERE valido_desde >= '2040-01-01') + (SELECT count(*) FROM vexterno.historia_ponto WHERE data_inclusao >= '2040-01-01')"
)

sql() {
    $COMO_POSTGRES psql $CONEXAO -X -q -v ON_ERROR_STOP=1 -d "$BANCO" "$@";
}

valor() {
    sql -At -c "$1";
}

bench() {
    local esquema=$1
    shift
    $COMO_POSTGRES env PGOPTIONS="-c search_path=$esquema" pgbench $CONEXAO -n -M prepared "$@" "$BANCO"
}

checar() {
    local falhas
    falhas=$(valor "SELECT coalesce(sum(falhas), 0) FROM ensaio.consistencia('$1')")
    if [ "$falhas" = 0 ]; then
        echo "  $2: consistente"
    else
        echo "  $2: $falhas falhas"
        sql -c "SELECT * FROM ensaio.consistencia('$1') WHERE falhas > 0"
    fi
}

for estrategia in $ESTRATEGIAS; do
    echo "== $estrategia"
    sql -c "TRUNCATE ${TABELAS[$estrategia]}"
    bench "$estrategia" -c 1 -D n=0 -t "$ESCALA" -f "$PASTA/escrita.sql" > /dev/null 2>&1
    checar "$estrategia" "carga de $ESCALA operações"

    antes=$(valor "SELECT ensaio.impressao('$estrategia')")
    sql > /dev/null <<SQL
BEGIN;
SET LOCAL search_path = $estrategia;
SELECT count(*) FILTER (WHERE ensaio.operar(l.id, 1 + g % 3))
  FROM generate_series(1, 1000) g
  JOIN ensaio.leitura l ON l.escala = $ESCALA AND l.consulta = 3 AND l.k = 1 + g % 10;
ROLLBACK;
SQL
    if sql > /dev/null 2>&1 <<SQL
SET search_path = $estrategia;
SET statement_timeout = '500ms';
SELECT count(*) FILTER (WHERE ensaio.operar(l.id, 1 + g % 3))
  FROM generate_series(1, 1000000) g
  JOIN ensaio.leitura l ON l.escala = $ESCALA AND l.consulta = 3 AND l.k = 1 + g % 10;
SQL
    then
        echo "  cancelamento: o comando terminou antes do tempo limite"
    fi
    depois=$(valor "SELECT ensaio.impressao('$estrategia')")
    if [ "$antes" = "$depois" ]; then
        echo "  rollback e cancelamento: nada mudou"
    else
        echo "  rollback e cancelamento: o estado mudou"
    fi
    checar "$estrategia" "rollback e cancelamento"

    bench "$estrategia" -c 1 -D n="$ESCALA" -t 100000 -f "$PASTA/escrita.sql" > /dev/null 2>&1 &
    sleep "$ESPERA"
    bash -c "$PARAR"
    wait || true
    bash -c "$INICIAR"
    until $COMO_POSTGRES pg_isready $CONEXAO -d "$BANCO" -q; do
        sleep 1
    done
    checar "$estrategia" "parada brusca"

    transacoes=$(bench "$estrategia" -c "$CLIENTES" -j "$CLIENTES" -T "$DURACAO" -D escala="$ESCALA" -f "$PASTA/concorrencia.sql" 2>&1 \
                 | sed -n 's/^number of transactions actually processed: \([0-9]*\).*/\1/p')
    aplicadas=$(valor "SELECT ${VERSOES[$estrategia]}")
    echo "  concorrência: $CLIENTES clientes, $transacoes operações, $aplicadas aplicadas, $((transacoes - aplicadas)) recusadas"
    checar "$estrategia" "concorrência"
done
