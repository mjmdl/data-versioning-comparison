\set k random(1, 10)
\set operacao random(1, 3)
SELECT ensaio.operar(id, :operacao) FROM ensaio.leitura WHERE escala = :escala AND consulta = 3 AND k = :k;
