\set i :i + 1
\set consulta (:i - 1) % 5 + 1
\set k (:i - 1) / 5 + 1
SELECT id FROM ensaio.leitura WHERE escala = :escala AND consulta = :consulta AND k = :k
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
\endif
