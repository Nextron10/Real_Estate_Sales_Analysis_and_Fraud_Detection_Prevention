-- Phase 1 step 1: run this against the Azure suryavan database.
-- SELECT reads information; aliases after AS label the output columns.
-- Expected Azure result: suryavan, pgadmin, PostgreSQL 17.x, ssl_enabled=true.
-- A local test instance may have a different version and no SSL.
SELECT current_database() AS database_name,
       current_user AS username,
       current_setting('server_version') AS postgres_version,
       (SELECT ssl
        FROM pg_stat_ssl
        WHERE pid = pg_backend_pid()) AS ssl_enabled;

-- This second result shows whether the business tables already exist.
-- Empty output means the seven tables have not been created in public.
-- An empty second result is not a SQL error; read the connection row above.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name IN (
      'plots', 'brokers', 'bookings', 'booking_buyers',
      'payment_schedule', 'government_charges', 'payments'
  )
ORDER BY table_name;
