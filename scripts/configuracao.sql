ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
ALTER SYSTEM SET autovacuum = off;
ALTER SYSTEM SET checkpoint_timeout = '1d';
ALTER SYSTEM SET max_wal_size = '8GB';
ALTER SYSTEM SET synchronous_commit = off;
