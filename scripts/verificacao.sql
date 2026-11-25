SELECT
    'departamento' AS tabela,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, nome
                FROM base.departamento
                EXCEPT
                SELECT id, nome
                FROM vinterno.departamento
                WHERE valido_ate = 'infinity'
            )
            UNION ALL
            (
                SELECT id, nome
                FROM vinterno.departamento
                WHERE valido_ate = 'infinity'
                EXCEPT
                SELECT id, nome
                FROM base.departamento
            )
        ) diferenca
    ) AS atual_vinterno,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, nome
                FROM base.departamento
                EXCEPT
                SELECT id, nome
                FROM vexterno.departamento
            )
            UNION ALL
            (
                SELECT id, nome
                FROM vexterno.departamento
                EXCEPT
                SELECT id, nome
                FROM base.departamento
            )
        ) diferenca
    ) AS atual_vexterno,
    (
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
    ) AS historia_aberta,
    (
        SELECT count(*)
        FROM (
            (
                SELECT entidade, valido_desde, valido_ate, nome
                FROM vinterno.departamento
                EXCEPT
                SELECT id, valido_desde, valido_ate, nome
                FROM vexterno.historia_departamento
            )
            UNION ALL
            (
                SELECT id, valido_desde, valido_ate, nome
                FROM vexterno.historia_departamento
                EXCEPT
                SELECT entidade, valido_desde, valido_ate, nome
                FROM vinterno.departamento
            )
        ) diferenca
    ) AS historico,
    (
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
    ) AS lacunas_vinterno,
    (
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
    ) AS lacunas_vexterno,
    (
        SELECT count(*)
        FROM (
            SELECT
                id = entidade AS propria,
                row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
            FROM vinterno.departamento
        ) versoes
        WHERE propria <> ultima
    ) AS id_vinterno
UNION ALL
SELECT
    'horario' AS tabela,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, departamento, inicio, fim, dia
                FROM base.horario
                EXCEPT
                SELECT id, departamento, inicio, fim, dia
                FROM vinterno.horario
                WHERE valido_ate = 'infinity'
            )
            UNION ALL
            (
                SELECT id, departamento, inicio, fim, dia
                FROM vinterno.horario
                WHERE valido_ate = 'infinity'
                EXCEPT
                SELECT id, departamento, inicio, fim, dia
                FROM base.horario
            )
        ) diferenca
    ) AS atual_vinterno,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, departamento, inicio, fim, dia
                FROM base.horario
                EXCEPT
                SELECT id, departamento, inicio, fim, dia
                FROM vexterno.horario
            )
            UNION ALL
            (
                SELECT id, departamento, inicio, fim, dia
                FROM vexterno.horario
                EXCEPT
                SELECT id, departamento, inicio, fim, dia
                FROM base.horario
            )
        ) diferenca
    ) AS atual_vexterno,
    (
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
    ) AS historia_aberta,
    (
        SELECT count(*)
        FROM (
            (
                SELECT entidade, valido_desde, valido_ate, departamento, inicio, fim, dia
                FROM vinterno.horario
                EXCEPT
                SELECT id, valido_desde, valido_ate, departamento, inicio, fim, dia
                FROM vexterno.historia_horario
            )
            UNION ALL
            (
                SELECT id, valido_desde, valido_ate, departamento, inicio, fim, dia
                FROM vexterno.historia_horario
                EXCEPT
                SELECT entidade, valido_desde, valido_ate, departamento, inicio, fim, dia
                FROM vinterno.horario
            )
        ) diferenca
    ) AS historico,
    (
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
    ) AS lacunas_vinterno,
    (
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
    ) AS lacunas_vexterno,
    (
        SELECT count(*)
        FROM (
            SELECT
                id = entidade AS propria,
                row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
            FROM vinterno.horario
        ) versoes
        WHERE propria <> ultima
    ) AS id_vinterno
UNION ALL
SELECT
    'funcionario' AS tabela,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM base.funcionario
                EXCEPT
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vinterno.funcionario
                WHERE valido_ate = 'infinity'
            )
            UNION ALL
            (
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vinterno.funcionario
                WHERE valido_ate = 'infinity'
                EXCEPT
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM base.funcionario
            )
        ) diferenca
    ) AS atual_vinterno,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM base.funcionario
                EXCEPT
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vexterno.funcionario
            )
            UNION ALL
            (
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vexterno.funcionario
                EXCEPT
                SELECT id, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM base.funcionario
            )
        ) diferenca
    ) AS atual_vexterno,
    (
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
    ) AS historia_aberta,
    (
        SELECT count(*)
        FROM (
            (
                SELECT entidade, valido_desde, valido_ate, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vinterno.funcionario
                EXCEPT
                SELECT id, valido_desde, valido_ate, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vexterno.historia_funcionario
            )
            UNION ALL
            (
                SELECT id, valido_desde, valido_ate, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vexterno.historia_funcionario
                EXCEPT
                SELECT entidade, valido_desde, valido_ate, nome_civil, nome_social, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra
                FROM vinterno.funcionario
            )
        ) diferenca
    ) AS historico,
    (
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
    ) AS lacunas_vinterno,
    (
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
    ) AS lacunas_vexterno,
    (
        SELECT count(*)
        FROM (
            SELECT
                id = entidade AS propria,
                row_number() OVER (PARTITION BY entidade ORDER BY valido_desde DESC) = 1 AS ultima
            FROM vinterno.funcionario
        ) versoes
        WHERE propria <> ultima
    ) AS id_vinterno
UNION ALL
SELECT
    'ferias' AS tabela,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM base.ferias
                EXCEPT
                SELECT ferias.id, ferias.funcionario, ferias.inicio, ferias.fim, ferias.status, ferias.observacao
                FROM vinterno.ferias
                JOIN vinterno.funcionario ON funcionario.id = ferias.funcionario
                WHERE
                    ferias.data_exclusao IS NULL AND
                    funcionario.valido_ate = 'infinity'
            )
            UNION ALL
            (
                SELECT ferias.id, ferias.funcionario, ferias.inicio, ferias.fim, ferias.status, ferias.observacao
                FROM vinterno.ferias
                JOIN vinterno.funcionario ON funcionario.id = ferias.funcionario
                WHERE
                    ferias.data_exclusao IS NULL AND
                    funcionario.valido_ate = 'infinity'
                EXCEPT
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM base.ferias
            )
        ) diferenca
    ) AS atual_vinterno,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM base.ferias
                EXCEPT
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM vexterno.ferias
            )
            UNION ALL
            (
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM vexterno.ferias
                EXCEPT
                SELECT id, funcionario, inicio, fim, status, observacao
                FROM base.ferias
            )
        ) diferenca
    ) AS atual_vexterno,
    (
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
    ) AS historia_aberta,
    (
        SELECT count(*)
        FROM (
            (
                SELECT entidade, data_inclusao, data_exclusao, funcionario, inicio, fim, status, observacao
                FROM vinterno.ferias
                EXCEPT
                SELECT id, data_inclusao, data_exclusao, funcionario, inicio, fim, status, observacao
                FROM vexterno.historia_ferias
            )
            UNION ALL
            (
                SELECT id, data_inclusao, data_exclusao, funcionario, inicio, fim, status, observacao
                FROM vexterno.historia_ferias
                EXCEPT
                SELECT entidade, data_inclusao, data_exclusao, funcionario, inicio, fim, status, observacao
                FROM vinterno.ferias
            )
        ) diferenca
    ) AS historico,
    (
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
    ) AS lacunas_vinterno,
    (
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
    ) AS lacunas_vexterno,
    (
        SELECT count(*)
        FROM (
            SELECT
                id = entidade AS propria,
                row_number() OVER (PARTITION BY entidade ORDER BY data_inclusao DESC) = 1 AS ultima
            FROM vinterno.ferias
        ) versoes
        WHERE propria <> ultima
    ) AS id_vinterno
UNION ALL
SELECT
    'ponto' AS tabela,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, funcionario, registro, tipo, justificativa
                FROM base.ponto
                EXCEPT
                SELECT ponto.id, ponto.funcionario, ponto.registro, ponto.tipo, ponto.justificativa
                FROM vinterno.ponto
                JOIN vinterno.funcionario ON funcionario.id = ponto.funcionario
                WHERE
                    ponto.data_exclusao IS NULL AND
                    funcionario.valido_ate = 'infinity'
            )
            UNION ALL
            (
                SELECT ponto.id, ponto.funcionario, ponto.registro, ponto.tipo, ponto.justificativa
                FROM vinterno.ponto
                JOIN vinterno.funcionario ON funcionario.id = ponto.funcionario
                WHERE
                    ponto.data_exclusao IS NULL AND
                    funcionario.valido_ate = 'infinity'
                EXCEPT
                SELECT id, funcionario, registro, tipo, justificativa
                FROM base.ponto
            )
        ) diferenca
    ) AS atual_vinterno,
    (
        SELECT count(*)
        FROM (
            (
                SELECT id, funcionario, registro, tipo, justificativa
                FROM base.ponto
                EXCEPT
                SELECT id, funcionario, registro, tipo, justificativa
                FROM vexterno.ponto
            )
            UNION ALL
            (
                SELECT id, funcionario, registro, tipo, justificativa
                FROM vexterno.ponto
                EXCEPT
                SELECT id, funcionario, registro, tipo, justificativa
                FROM base.ponto
            )
        ) diferenca
    ) AS atual_vexterno,
    (
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
    ) AS historia_aberta,
    (
        SELECT count(*)
        FROM (
            (
                SELECT entidade, data_inclusao, data_exclusao, funcionario, registro, tipo, justificativa
                FROM vinterno.ponto
                EXCEPT
                SELECT id, data_inclusao, data_exclusao, funcionario, registro, tipo, justificativa
                FROM vexterno.historia_ponto
            )
            UNION ALL
            (
                SELECT id, data_inclusao, data_exclusao, funcionario, registro, tipo, justificativa
                FROM vexterno.historia_ponto
                EXCEPT
                SELECT entidade, data_inclusao, data_exclusao, funcionario, registro, tipo, justificativa
                FROM vinterno.ponto
            )
        ) diferenca
    ) AS historico,
    (
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
    ) AS lacunas_vinterno,
    (
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
    ) AS lacunas_vexterno,
    (
        SELECT count(*)
        FROM (
            SELECT
                id = entidade AS propria,
                row_number() OVER (PARTITION BY entidade ORDER BY data_inclusao DESC) = 1 AS ultima
            FROM vinterno.ponto
        ) versoes
        WHERE propria <> ultima
    ) AS id_vinterno;
