BEGIN;

CREATE OR REPLACE FUNCTION ensaio.consistencia(_estrategia text)
    RETURNS TABLE (tabela text, regra text, falhas bigint)
    LANGUAGE plpgsql
    STABLE AS $$
BEGIN
    IF _estrategia = 'vinterno' THEN
        RETURN QUERY
        SELECT 'departamento', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT entidade
                FROM vinterno.departamento
                WHERE valido_ate = 'infinity'
                GROUP BY entidade
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'departamento', 'periodo', (
            SELECT count(*) FROM vinterno.departamento WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'departamento', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY entidade ORDER BY valido_desde) AS seguinte
                FROM vinterno.departamento
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'departamento', 'dados_atuais', (
            SELECT count(*)
            FROM (
                SELECT
                    id = entidade AS propria,
                    row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
                FROM vinterno.departamento
            ) versoes
            WHERE propria <> ultima
        )
        UNION ALL
        SELECT 'departamento', 'referencias', 0::bigint
        UNION ALL
        SELECT 'horario', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT entidade
                FROM vinterno.horario
                WHERE valido_ate = 'infinity'
                GROUP BY entidade
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'horario', 'periodo', (
            SELECT count(*) FROM vinterno.horario WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'horario', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY entidade ORDER BY valido_desde) AS seguinte
                FROM vinterno.horario
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'horario', 'dados_atuais', (
            SELECT count(*)
            FROM (
                SELECT
                    id = entidade AS propria,
                    row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
                FROM vinterno.horario
            ) versoes
            WHERE propria <> ultima
        )
        UNION ALL
        SELECT 'horario', 'referencias', (
            SELECT count(*)
            FROM vinterno.horario
            LEFT JOIN (
                SELECT
                    entidade AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vinterno.departamento
                GROUP BY entidade
            ) cobertura ON cobertura.alvo = horario.departamento
            WHERE
                horario.departamento IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > horario.valido_desde OR
                    cobertura.ate < horario.valido_ate
                )
        )
        UNION ALL
        SELECT 'funcionario', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT entidade
                FROM vinterno.funcionario
                WHERE valido_ate = 'infinity'
                GROUP BY entidade
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'funcionario', 'periodo', (
            SELECT count(*) FROM vinterno.funcionario WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'funcionario', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY entidade ORDER BY valido_desde) AS seguinte
                FROM vinterno.funcionario
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'funcionario', 'dados_atuais', (
            SELECT count(*)
            FROM (
                SELECT
                    id = entidade AS propria,
                    row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
                FROM vinterno.funcionario
            ) versoes
            WHERE propria <> ultima
        )
        UNION ALL
        SELECT 'funcionario', 'referencias', (
            SELECT count(*)
            FROM vinterno.funcionario
            LEFT JOIN (
                SELECT
                    entidade AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vinterno.departamento
                GROUP BY entidade
            ) cobertura ON cobertura.alvo = funcionario.departamento
            WHERE
                funcionario.departamento IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > funcionario.valido_desde OR
                    cobertura.ate < funcionario.valido_ate
                )
        ) + (
            SELECT count(*)
            FROM vinterno.funcionario
            LEFT JOIN (
                SELECT
                    entidade AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vinterno.funcionario
                GROUP BY entidade
            ) cobertura ON cobertura.alvo = funcionario.funcionario_lider
            WHERE
                funcionario.funcionario_lider IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > funcionario.valido_desde OR
                    cobertura.ate < funcionario.valido_ate
                )
        )
        UNION ALL
        SELECT 'ferias', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT entidade
                FROM vinterno.ferias
                WHERE data_exclusao IS NULL
                GROUP BY entidade
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'ferias', 'periodo', (
            SELECT count(*)
            FROM vinterno.ferias
            WHERE
                data_exclusao IS NOT NULL AND
                data_inclusao >= data_exclusao
        )
        UNION ALL
        SELECT 'ferias', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    data_exclusao AS ate,
                    lead(data_inclusao) OVER (PARTITION BY entidade ORDER BY data_inclusao) AS seguinte
                FROM vinterno.ferias
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'ferias', 'dados_atuais', (
            SELECT count(*)
            FROM (
                SELECT
                    id = entidade AS propria,
                    row_number() OVER (PARTITION BY entidade ORDER BY data_inclusao DESC) = 1 AS ultima
                FROM vinterno.ferias
            ) versoes
            WHERE propria <> ultima
        )
        UNION ALL
        SELECT 'ferias', 'referencias', (
            SELECT count(*)
            FROM vinterno.ferias
            WHERE NOT EXISTS (
                SELECT 1
                FROM vinterno.funcionario
                WHERE
                    funcionario.entidade = ferias.funcionario AND
                    funcionario.valido_desde <= ferias.data_inclusao AND
                    ferias.data_inclusao < funcionario.valido_ate
            )
        )
        UNION ALL
        SELECT 'ponto', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT entidade
                FROM vinterno.ponto
                WHERE data_exclusao IS NULL
                GROUP BY entidade
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'ponto', 'periodo', (
            SELECT count(*)
            FROM vinterno.ponto
            WHERE
                data_exclusao IS NOT NULL AND
                data_inclusao >= data_exclusao
        )
        UNION ALL
        SELECT 'ponto', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    data_exclusao AS ate,
                    lead(data_inclusao) OVER (PARTITION BY entidade ORDER BY data_inclusao) AS seguinte
                FROM vinterno.ponto
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'ponto', 'dados_atuais', (
            SELECT count(*)
            FROM (
                SELECT
                    id = entidade AS propria,
                    row_number() OVER (PARTITION BY entidade ORDER BY data_inclusao DESC) = 1 AS ultima
                FROM vinterno.ponto
            ) versoes
            WHERE propria <> ultima
        )
        UNION ALL
        SELECT 'ponto', 'referencias', (
            SELECT count(*)
            FROM vinterno.ponto
            WHERE NOT EXISTS (
                SELECT 1
                FROM vinterno.funcionario
                WHERE
                    funcionario.entidade = ponto.funcionario AND
                    funcionario.valido_desde <= ponto.data_inclusao AND
                    ponto.data_inclusao < funcionario.valido_ate
            )
        );
    ELSIF _estrategia = 'vexterno' THEN
        RETURN QUERY
        SELECT 'departamento', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT id
                FROM vexterno.historia_departamento
                WHERE valido_ate = 'infinity'
                GROUP BY id
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'departamento', 'periodo', (
            SELECT count(*) FROM vexterno.historia_departamento WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'departamento', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY id ORDER BY valido_desde) AS seguinte
                FROM vexterno.historia_departamento
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'departamento', 'dados_atuais', (
            SELECT count(*)
            FROM (
                (
                    SELECT id, nome
                    FROM vexterno.departamento
                    EXCEPT
                    SELECT id, nome
                    FROM vexterno.historia_departamento
                    WHERE valido_ate = 'infinity'
                )
                UNION ALL
                (
                    SELECT id, nome
                    FROM vexterno.historia_departamento
                    WHERE valido_ate = 'infinity'
                    EXCEPT
                    SELECT id, nome
                    FROM vexterno.departamento
                )
            ) diferenca
        )
        UNION ALL
        SELECT 'departamento', 'referencias', 0::bigint
        UNION ALL
        SELECT 'horario', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT id
                FROM vexterno.historia_horario
                WHERE valido_ate = 'infinity'
                GROUP BY id
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'horario', 'periodo', (
            SELECT count(*) FROM vexterno.historia_horario WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'horario', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY id ORDER BY valido_desde) AS seguinte
                FROM vexterno.historia_horario
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'horario', 'dados_atuais', (
            SELECT count(*)
            FROM (
                (
                    SELECT id, departamento, inicio, fim, dia
                    FROM vexterno.horario
                    EXCEPT
                    SELECT id, departamento, inicio, fim, dia
                    FROM vexterno.historia_horario
                    WHERE valido_ate = 'infinity'
                )
                UNION ALL
                (
                    SELECT id, departamento, inicio, fim, dia
                    FROM vexterno.historia_horario
                    WHERE valido_ate = 'infinity'
                    EXCEPT
                    SELECT id, departamento, inicio, fim, dia
                    FROM vexterno.horario
                )
            ) diferenca
        )
        UNION ALL
        SELECT 'horario', 'referencias', (
            SELECT count(*)
            FROM vexterno.historia_horario
            LEFT JOIN (
                SELECT
                    id AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vexterno.historia_departamento
                GROUP BY id
            ) cobertura ON cobertura.alvo = historia_horario.departamento
            WHERE
                historia_horario.departamento IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > historia_horario.valido_desde OR
                    cobertura.ate < historia_horario.valido_ate
                )
        )
        UNION ALL
        SELECT 'funcionario', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT id
                FROM vexterno.historia_funcionario
                WHERE valido_ate = 'infinity'
                GROUP BY id
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'funcionario', 'periodo', (
            SELECT count(*) FROM vexterno.historia_funcionario WHERE valido_desde >= valido_ate
        )
        UNION ALL
        SELECT 'funcionario', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    valido_ate AS ate,
                    lead(valido_desde) OVER (PARTITION BY id ORDER BY valido_desde) AS seguinte
                FROM vexterno.historia_funcionario
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'funcionario', 'dados_atuais', (
            SELECT count(*)
            FROM (
                (
                    SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                    FROM vexterno.funcionario
                    EXCEPT
                    SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                    FROM vexterno.historia_funcionario
                    WHERE valido_ate = 'infinity'
                )
                UNION ALL
                (
                    SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                    FROM vexterno.historia_funcionario
                    WHERE valido_ate = 'infinity'
                    EXCEPT
                    SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                    FROM vexterno.funcionario
                )
            ) diferenca
        )
        UNION ALL
        SELECT 'funcionario', 'referencias', (
            SELECT count(*)
            FROM vexterno.historia_funcionario
            LEFT JOIN (
                SELECT
                    id AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vexterno.historia_departamento
                GROUP BY id
            ) cobertura ON cobertura.alvo = historia_funcionario.departamento
            WHERE
                historia_funcionario.departamento IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > historia_funcionario.valido_desde OR
                    cobertura.ate < historia_funcionario.valido_ate
                )
        ) + (
            SELECT count(*)
            FROM vexterno.historia_funcionario
            LEFT JOIN (
                SELECT
                    id AS alvo,
                    min(valido_desde) AS de,
                    max(valido_ate) AS ate
                FROM vexterno.historia_funcionario
                GROUP BY id
            ) cobertura ON cobertura.alvo = historia_funcionario.funcionario_lider
            WHERE
                historia_funcionario.funcionario_lider IS NOT NULL AND
                (
                    cobertura.alvo IS NULL OR
                    cobertura.de > historia_funcionario.valido_desde OR
                    cobertura.ate < historia_funcionario.valido_ate
                )
        )
        UNION ALL
        SELECT 'ferias', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT id
                FROM vexterno.historia_ferias
                WHERE data_exclusao IS NULL
                GROUP BY id
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'ferias', 'periodo', (
            SELECT count(*)
            FROM vexterno.historia_ferias
            WHERE
                data_exclusao IS NOT NULL AND
                data_inclusao >= data_exclusao
        )
        UNION ALL
        SELECT 'ferias', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    data_exclusao AS ate,
                    lead(data_inclusao) OVER (PARTITION BY id ORDER BY data_inclusao) AS seguinte
                FROM vexterno.historia_ferias
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'ferias', 'dados_atuais', (
            SELECT count(*)
            FROM (
                (
                    SELECT id, funcionario, inicio, fim, status, observacao
                    FROM vexterno.ferias
                    EXCEPT
                    SELECT historia_ferias.id, historia_ferias.funcionario, historia_ferias.inicio, historia_ferias.fim, historia_ferias.status, historia_ferias.observacao
                    FROM vexterno.historia_ferias
                    JOIN vexterno.funcionario ON funcionario.id = historia_ferias.funcionario
                    WHERE historia_ferias.data_exclusao IS NULL
                )
                UNION ALL
                (
                    SELECT historia_ferias.id, historia_ferias.funcionario, historia_ferias.inicio, historia_ferias.fim, historia_ferias.status, historia_ferias.observacao
                    FROM vexterno.historia_ferias
                    JOIN vexterno.funcionario ON funcionario.id = historia_ferias.funcionario
                    WHERE historia_ferias.data_exclusao IS NULL
                    EXCEPT
                    SELECT id, funcionario, inicio, fim, status, observacao
                    FROM vexterno.ferias
                )
            ) diferenca
        )
        UNION ALL
        SELECT 'ferias', 'referencias', (
            SELECT count(*)
            FROM vexterno.historia_ferias
            WHERE NOT EXISTS (
                SELECT 1
                FROM vexterno.historia_funcionario
                WHERE
                    historia_funcionario.id = historia_ferias.funcionario AND
                    historia_funcionario.valido_desde <= historia_ferias.data_inclusao AND
                    historia_ferias.data_inclusao < historia_funcionario.valido_ate
            )
        )
        UNION ALL
        SELECT 'ponto', 'vigente_unica', (
            SELECT count(*)
            FROM (
                SELECT id
                FROM vexterno.historia_ponto
                WHERE data_exclusao IS NULL
                GROUP BY id
                HAVING count(*) > 1
            ) abertas
        )
        UNION ALL
        SELECT 'ponto', 'periodo', (
            SELECT count(*)
            FROM vexterno.historia_ponto
            WHERE
                data_exclusao IS NOT NULL AND
                data_inclusao >= data_exclusao
        )
        UNION ALL
        SELECT 'ponto', 'sobreposicao_lacuna', (
            SELECT count(*)
            FROM (
                SELECT
                    data_exclusao AS ate,
                    lead(data_inclusao) OVER (PARTITION BY id ORDER BY data_inclusao) AS seguinte
                FROM vexterno.historia_ponto
            ) consecutivas
            WHERE
                seguinte IS NOT NULL AND
                seguinte IS DISTINCT FROM ate
        )
        UNION ALL
        SELECT 'ponto', 'dados_atuais', (
            SELECT count(*)
            FROM (
                (
                    SELECT id, funcionario, registro, tipo, justificativa
                    FROM vexterno.ponto
                    EXCEPT
                    SELECT historia_ponto.id, historia_ponto.funcionario, historia_ponto.registro, historia_ponto.tipo, historia_ponto.justificativa
                    FROM vexterno.historia_ponto
                    JOIN vexterno.funcionario ON funcionario.id = historia_ponto.funcionario
                    WHERE historia_ponto.data_exclusao IS NULL
                )
                UNION ALL
                (
                    SELECT historia_ponto.id, historia_ponto.funcionario, historia_ponto.registro, historia_ponto.tipo, historia_ponto.justificativa
                    FROM vexterno.historia_ponto
                    JOIN vexterno.funcionario ON funcionario.id = historia_ponto.funcionario
                    WHERE historia_ponto.data_exclusao IS NULL
                    EXCEPT
                    SELECT id, funcionario, registro, tipo, justificativa
                    FROM vexterno.ponto
                )
            ) diferenca
        )
        UNION ALL
        SELECT 'ponto', 'referencias', (
            SELECT count(*)
            FROM vexterno.historia_ponto
            WHERE NOT EXISTS (
                SELECT 1
                FROM vexterno.historia_funcionario
                WHERE
                    historia_funcionario.id = historia_ponto.funcionario AND
                    historia_funcionario.valido_desde <= historia_ponto.data_inclusao AND
                    historia_ponto.data_inclusao < historia_funcionario.valido_ate
            )
        );
    ELSE
        RAISE EXCEPTION 'Estratégia sem regras de consistência: %.', _estrategia;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION ensaio.impressao(_estrategia text) RETURNS text LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF _estrategia = 'base' THEN
        RETURN (
            SELECT md5(string_agg(resumo, '' ORDER BY tabela))
            FROM (
                SELECT
                    'departamento' AS tabela,
                    md5(string_agg(departamento::text, '' ORDER BY departamento::text)) AS resumo
                FROM base.departamento
                UNION ALL
                SELECT
                    'horario' AS tabela,
                    md5(string_agg(horario::text, '' ORDER BY horario::text)) AS resumo
                FROM base.horario
                UNION ALL
                SELECT
                    'funcionario' AS tabela,
                    md5(string_agg(funcionario::text, '' ORDER BY funcionario::text)) AS resumo
                FROM base.funcionario
                UNION ALL
                SELECT
                    'ferias' AS tabela,
                    md5(string_agg(ferias::text, '' ORDER BY ferias::text)) AS resumo
                FROM base.ferias
                UNION ALL
                SELECT
                    'ponto' AS tabela,
                    md5(string_agg(ponto::text, '' ORDER BY ponto::text)) AS resumo
                FROM base.ponto
            ) resumos
        );
    ELSIF _estrategia = 'vinterno' THEN
        RETURN (
            SELECT md5(string_agg(resumo, '' ORDER BY tabela))
            FROM (
                SELECT
                    'departamento' AS tabela,
                    md5(string_agg(departamento::text, '' ORDER BY departamento::text)) AS resumo
                FROM vinterno.departamento
                UNION ALL
                SELECT
                    'horario' AS tabela,
                    md5(string_agg(horario::text, '' ORDER BY horario::text)) AS resumo
                FROM vinterno.horario
                UNION ALL
                SELECT
                    'funcionario' AS tabela,
                    md5(string_agg(funcionario::text, '' ORDER BY funcionario::text)) AS resumo
                FROM vinterno.funcionario
                UNION ALL
                SELECT
                    'ferias' AS tabela,
                    md5(string_agg(ferias::text, '' ORDER BY ferias::text)) AS resumo
                FROM vinterno.ferias
                UNION ALL
                SELECT
                    'ponto' AS tabela,
                    md5(string_agg(ponto::text, '' ORDER BY ponto::text)) AS resumo
                FROM vinterno.ponto
            ) resumos
        );
    ELSIF _estrategia = 'vexterno' THEN
        RETURN (
            SELECT md5(string_agg(resumo, '' ORDER BY tabela))
            FROM (
                SELECT
                    'departamento' AS tabela,
                    md5(string_agg(departamento::text, '' ORDER BY departamento::text)) AS resumo
                FROM vexterno.departamento
                UNION ALL
                SELECT
                    'horario' AS tabela,
                    md5(string_agg(horario::text, '' ORDER BY horario::text)) AS resumo
                FROM vexterno.horario
                UNION ALL
                SELECT
                    'funcionario' AS tabela,
                    md5(string_agg(funcionario::text, '' ORDER BY funcionario::text)) AS resumo
                FROM vexterno.funcionario
                UNION ALL
                SELECT
                    'ferias' AS tabela,
                    md5(string_agg(ferias::text, '' ORDER BY ferias::text)) AS resumo
                FROM vexterno.ferias
                UNION ALL
                SELECT
                    'ponto' AS tabela,
                    md5(string_agg(ponto::text, '' ORDER BY ponto::text)) AS resumo
                FROM vexterno.ponto
                UNION ALL
                SELECT
                    'historia_departamento' AS tabela,
                    md5(string_agg(historia_departamento::text, '' ORDER BY historia_departamento::text)) AS resumo
                FROM vexterno.historia_departamento
                UNION ALL
                SELECT
                    'historia_horario' AS tabela,
                    md5(string_agg(historia_horario::text, '' ORDER BY historia_horario::text)) AS resumo
                FROM vexterno.historia_horario
                UNION ALL
                SELECT
                    'historia_funcionario' AS tabela,
                    md5(string_agg(historia_funcionario::text, '' ORDER BY historia_funcionario::text)) AS resumo
                FROM vexterno.historia_funcionario
                UNION ALL
                SELECT
                    'historia_ferias' AS tabela,
                    md5(string_agg(historia_ferias::text, '' ORDER BY historia_ferias::text)) AS resumo
                FROM vexterno.historia_ferias
                UNION ALL
                SELECT
                    'historia_ponto' AS tabela,
                    md5(string_agg(historia_ponto::text, '' ORDER BY historia_ponto::text)) AS resumo
                FROM vexterno.historia_ponto
            ) resumos
        );
    END IF;
    RAISE EXCEPTION 'Estratégia desconhecida: %.', _estrategia;
END;
$$;

CREATE OR REPLACE FUNCTION ensaio.operar(_alvo uuid, _operacao integer) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    PERFORM set_config('versionamento.agora', (clock_timestamp() + interval '20 years')::text, true);
    IF _operacao = 1 THEN
        UPDATE funcionario SET salario = salario + 1 WHERE id = _alvo;
    ELSIF _operacao = 2 THEN
        UPDATE funcionario
        SET cargo = CASE WHEN cargo = 'Analista' THEN 'Gerente' ELSE 'Analista' END
        WHERE id = _alvo;
    ELSE
        INSERT INTO ponto (id, funcionario, registro, tipo)
        VALUES (gen_random_uuid(), _alvo, clock_timestamp() + interval '20 years', 'entrada');
    END IF;
    RETURN FOUND;
EXCEPTION WHEN OTHERS THEN
    RETURN false;
END;
$$;

COMMIT;
