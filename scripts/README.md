# Scripts

Ordem de execução:

```sh
# 1. Configurar o servidor PostgreSQL:
psql -d versionamento -f configuracao.sql
systemctl restart postgresql-17

# 2. Criar os esquemas principais:
psql -d versionamento -f base.ddl -f vinterno.ddl -f vexterno.ddl

# 3. Criar os esquemas auxiliares:
psql -d versionamento -f ensaio.ddl -f leitura.ddl -f consistencia.ddl -f resultado.ddl

# 4. Gerar o plano e as leituras:
psql -d versionamento -c 'CALL ensaio.gerar_plano()' -c 'CALL ensaio.gerar_leituras(100000)' -c 'CALL ensaio.gerar_leituras(1000000)'

# 5. Executar os testes:
./executar.sh

# 6. Gerar o relatório:
psql -d versionamento -f relatorio.sql > relatorio.txt

# 7. Testar a resistência:
PARAR="systemctl kill --signal=SIGKILL postgresql-17" INICIAR="systemctl start postgresql-17" ./resistencia.sh | tee resistencia.txt
```

## Arquivos

| Arquivo | Função |
|---|---|
| `configuracao.sql` | Normaliza o banco PostgreSQL para as configurações necessárias. |
| `base.ddl` | Cria o esquema sem versionamento. |
| `vinterno.ddl` | Cria o versionamento interno: as versões ficam na própria tabela. |
| `vexterno.ddl` | Cria o versionamento externo: as versões ficam nas tabelas `historia_*`. |
| `ensaio.ddl` | Gera o plano determinístico de 1 milhão de escritas. |
| `leitura.ddl` | Gera os parâmetros determinísticos das 15 leituras. |
| `consistencia.ddl` | Cria funções que conferem as regras do versionamento e auxiliam o teste de resistência. |
| `resultado.ddl` | Tabelas onde as medições ficam gravadas. |
| `escrita.sql` | Script do pgbench que executa o plano. |
| `leitura_base.sql`, `leitura_vinterno.sql`, `leitura_vexterno.sql` | Scripts do pgbench com as leituras de cada estratégia. |
| `verificacao.sql` | Compara o estado atual e o histórico das três estratégias. |
| `executar.sh` | Roda escrita e leitura em cada estratégia, escala e repetição, e grava os resultados no esquema `resultado`. |
| `relatorio.sql` | Calcula média, desvio-padrão e razão entre as escalas. |
| `resistencia.sh`, `concorrencia.sql` | Testam cancelamento, parada brusca e carga concorrente. |
