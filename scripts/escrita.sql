\set n :n + 1
SELECT set_config('versionamento.agora', instante::text, false) AS agora, comando, id, departamento, funcionario, funcionario_lider, nome, nome_civil, documento, nascimento, genero, email, telefone, endereco, cargo, salario, percentual_hora_extra, dia, hora_inicio, hora_fim, registro, tipo, justificativa, inicio, fim, status FROM ensaio.plano WHERE n = :n
\gset
\if :comando = 1
INSERT INTO departamento (id, nome) VALUES (:id, :nome);
\elif :comando = 2
UPDATE departamento SET nome = :nome WHERE id = :id;
\elif :comando = 3
DELETE FROM departamento WHERE id = :id;
\elif :comando = 4
INSERT INTO horario (id, departamento, dia, inicio, fim) VALUES (:id, :departamento, :dia, :hora_inicio, :hora_fim);
\elif :comando = 5
UPDATE horario SET inicio = :hora_inicio, fim = :hora_fim WHERE id = :id;
\elif :comando = 6
DELETE FROM horario WHERE id = :id;
\elif :comando = 7
INSERT INTO funcionario (id, nome_civil, documento, nascimento, genero, email, telefone, endereco, funcionario_lider, departamento, cargo, salario, percentual_hora_extra) VALUES (:id, :nome_civil, :documento, :nascimento, :genero, :email, :telefone, :endereco, nullif(:funcionario_lider, '')::uuid, :departamento, :cargo, :salario, :percentual_hora_extra);
\elif :comando = 8
UPDATE funcionario SET cargo = :cargo WHERE id = :id;
\elif :comando = 9
UPDATE funcionario SET salario = :salario WHERE id = :id;
\elif :comando = 10
UPDATE funcionario SET departamento = :departamento WHERE id = :id;
\elif :comando = 11
UPDATE funcionario SET funcionario_lider = nullif(:funcionario_lider, '')::uuid WHERE id = :id;
\elif :comando = 12
DELETE FROM funcionario WHERE id = :id;
\elif :comando = 13
INSERT INTO ponto (id, funcionario, registro, tipo) VALUES (:id, :funcionario, :registro, :tipo);
\elif :comando = 14
UPDATE ponto SET registro = :registro, justificativa = :justificativa WHERE id = :id;
\elif :comando = 15
UPDATE ponto SET justificativa = :justificativa WHERE id = :id;
\elif :comando = 16
DELETE FROM ponto WHERE id = :id;
\elif :comando = 17
INSERT INTO ferias (id, funcionario, inicio, fim, status) VALUES (:id, :funcionario, :inicio, :fim, :status);
\elif :comando = 18
UPDATE ferias SET status = :status WHERE id = :id;
\endif
