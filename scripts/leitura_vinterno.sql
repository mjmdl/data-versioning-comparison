\set i :i + 1
\set consulta (:i - 1) % 15 + 1
\set k (:i - 1) / 15 + 1
SELECT id, instante FROM ensaio.leitura WHERE escala = :escala AND consulta = :consulta AND k = :k
\gset
\if :consulta = 1
SELECT * FROM departamento WHERE id = :id AND valido_ate = 'infinity';
\elif :consulta = 2
SELECT * FROM horario WHERE id = :id AND valido_ate = 'infinity';
\elif :consulta = 3
SELECT * FROM funcionario WHERE id = :id AND valido_ate = 'infinity';
\elif :consulta = 4
SELECT ferias.* FROM ferias JOIN funcionario ON funcionario.id = ferias.funcionario WHERE ferias.id = :id AND ferias.data_exclusao IS NULL AND funcionario.valido_ate = 'infinity';
\elif :consulta = 5
SELECT ponto.* FROM ponto JOIN funcionario ON funcionario.id = ponto.funcionario WHERE ponto.id = :id AND ponto.data_exclusao IS NULL AND funcionario.valido_ate = 'infinity';
\elif :consulta = 6
SELECT * FROM departamento WHERE entidade = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 7
SELECT * FROM horario WHERE entidade = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 8
SELECT * FROM funcionario WHERE entidade = :id AND valido_desde <= :instante AND :instante < valido_ate;
\elif :consulta = 9
SELECT * FROM ferias WHERE entidade = :id AND data_inclusao <= :instante AND (data_exclusao IS NULL OR :instante < data_exclusao);
\elif :consulta = 10
SELECT * FROM ponto WHERE entidade = :id AND data_inclusao <= :instante AND (data_exclusao IS NULL OR :instante < data_exclusao);
\elif :consulta = 11
SELECT * FROM departamento WHERE entidade = :id ORDER BY valido_desde;
\elif :consulta = 12
SELECT * FROM horario WHERE entidade = :id ORDER BY valido_desde;
\elif :consulta = 13
SELECT * FROM funcionario WHERE entidade = :id ORDER BY valido_desde;
\elif :consulta = 14
SELECT * FROM ferias WHERE entidade = :id ORDER BY data_inclusao;
\elif :consulta = 15
SELECT * FROM ponto WHERE entidade = :id ORDER BY data_inclusao;
\endif
