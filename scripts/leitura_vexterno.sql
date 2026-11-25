\set i :i + 1
\set consulta (:i - 1) % 15 + 1
\set k (:i - 1) / 15 + 1
SELECT id, instante FROM ensaio.leitura WHERE escala = :escala AND consulta = :consulta AND k = :k
\gset
\if :consulta = 1
SELECT * FROM departamento WHERE id = :id;
\elif :consulta = 2
SELECT * FROM horario WHERE id = :id;
\elif :consulta = 3
SELECT * FROM funcionario WHERE id = :id;
\elif :consulta = 4
SELECT * FROM ferias WHERE id = :id;
\elif :consulta = 5
SELECT * FROM ponto WHERE id = :id;
\elif :consulta = 6
SELECT * FROM historia_departamento WHERE id = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 7
SELECT * FROM historia_horario WHERE id = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 8
SELECT * FROM historia_funcionario WHERE id = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 9
SELECT * FROM historia_ferias WHERE id = :id AND data_inclusao <= :instante AND (data_exclusao IS NULL OR :instante < data_exclusao);
\elif :consulta = 10
SELECT * FROM historia_ponto WHERE id = :id AND data_inclusao <= :instante AND (data_exclusao IS NULL OR :instante < data_exclusao);
\elif :consulta = 11
SELECT * FROM historia_departamento WHERE id = :id ORDER BY valido_desde;
\elif :consulta = 12
SELECT * FROM historia_horario WHERE id = :id ORDER BY valido_desde;
\elif :consulta = 13
SELECT * FROM historia_funcionario WHERE id = :id ORDER BY valido_desde;
\elif :consulta = 14
SELECT * FROM historia_ferias WHERE id = :id ORDER BY data_inclusao;
\elif :consulta = 15
SELECT * FROM historia_ponto WHERE id = :id ORDER BY data_inclusao;
\endif
