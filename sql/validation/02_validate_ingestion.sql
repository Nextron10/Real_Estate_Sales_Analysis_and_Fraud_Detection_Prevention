-- Phase 1 step 3: execute after all seven ADF Copy activities succeed.
-- This file is read-only. It validates the approved, unchanged source snapshot.
-- Expected output: one SUMMARY row with passed=true, and no failed check rows.
-- Totals include claims, attempts, transfers and credits; they are NOT sales KPIs.
-- status=NOT_LOADED means the tables exist but contain no source records.
-- Failed check rows are query results, not PostgreSQL syntax errors.
BEGIN TRANSACTION READ ONLY;

DO $guard$
BEGIN
    IF current_database() <> 'suryavan' THEN
        RAISE EXCEPTION 'Connect to suryavan before validating ingestion.';
    END IF;
END;
$guard$;

-- CTEs label each validation section; they do not create database objects.
-- The checks section feeds both the summary and the individual failure rows.
-- 1. Compare source row counts and financial control totals.
WITH table_counts(tbl, expected, actual) AS (
    SELECT 'plots', 2000, COUNT(*) FROM public.plots
    UNION ALL
    SELECT 'brokers', 8, COUNT(*) FROM public.brokers
    UNION ALL
    SELECT 'bookings', 1540, COUNT(*) FROM public.bookings
    UNION ALL
    SELECT 'booking_buyers', 2187, COUNT(*) FROM public.booking_buyers
    UNION ALL
    SELECT 'payment_schedule', 10951, COUNT(*) FROM public.payment_schedule
    UNION ALL
    SELECT 'government_charges', 5560, COUNT(*) FROM public.government_charges
    UNION ALL
    SELECT 'payments', 16857, COUNT(*) FROM public.payments
),
money_totals(control, expected, actual) AS (
    SELECT 'bookings_price', 24805840000.00, COALESCE(SUM(price), 0) FROM public.bookings
    UNION ALL
    SELECT 'schedule_due', 23820168866.61, COALESCE(SUM(due_amt), 0) FROM public.payment_schedule
    UNION ALL
    SELECT 'ledger_amount', 19454188174.97, COALESCE(SUM(amount), 0) FROM public.payments
    UNION ALL
    SELECT 'government_amount', 1663435233.36, COALESCE(SUM(amount), 0) FROM public.government_charges
    UNION ALL
    SELECT 'government_nonrefund', 20000.00, COALESCE(SUM(nonrefund_amt), 0) FROM public.government_charges
),
-- 2. Compare ledger categories, including missing or unexpected categories.
expected_ledger(component, entry_type, verify_status, row_count, amount) AS (
    VALUES
        ('COMMISSION', 'COMMISSION_PAID', 'Verified', 889, 281095700.00),
        ('COMMISSION', 'COMMISSION_RECOVERED', 'Verified', 64, 7924400.00),
        ('COMMISSION', 'OFFSET_RECOVERY', 'Verified', 45, 3376600.00),
        ('COMMISSION', 'OFFSET_WITHHELD', 'Verified', 45, 3376600.00),
        ('GOVT', 'RECEIPT', 'Verified', 4170, 1439562483.36),
        ('GOVT', 'REFUND', 'Verified', 456, 134684033.34),
        ('GOVT', 'REMITTANCE', 'Verified', 1799, 606536100.02),
        ('LATE_FEE', 'RECEIPT', 'Verified', 25, 31383.25),
        ('PLOT', 'RECEIPT', 'Pending', 7, 2665000.00),
        ('PLOT', 'RECEIPT', 'Rejected', 5, 1500000.00),
        ('PLOT', 'RECEIPT', 'Verified', 4688, 15702268921.25),
        ('PLOT', 'REFUND', 'Verified', 134, 537088000.00),
        ('PLOT', 'TDS_CREDIT', 'Verified', 4409, 148128953.75),
        ('PLOT', 'TRANSFER_IN', 'Verified', 91, 292975000.00),
        ('PLOT', 'TRANSFER_OUT', 'Verified', 30, 292975000.00)
),
actual_ledger AS (
    SELECT component, entry_type, verify_status, COUNT(*) AS row_count, SUM(amount) AS amount
    FROM public.payments
    GROUP BY component, entry_type, verify_status
),
-- 3. Check column types and whether NULL is allowed.
expected_columns(tbl, col, data_type, is_nullable) AS (
    VALUES
        ('plots', 'plot_id', 'text', 'NO'),
        ('plots', 'zone', 'text', 'NO'),
        ('plots', 'block', 'text', 'NO'),
        ('plots', 'plot_no', 'integer', 'NO'),
        ('plots', 'area_gaj', 'integer', 'NO'),
        ('plots', 'is_corner', 'boolean', 'NO'),
        ('plots', 'status', 'text', 'NO'),
        ('plots', 'block_reason', 'text', 'YES'),
        ('brokers', 'broker_id', 'text', 'NO'),
        ('brokers', 'name', 'text', 'NO'),
        ('brokers', 'joined_on', 'date', 'NO'),
        ('brokers', 'is_active', 'boolean', 'NO'),
        ('bookings', 'booking_id', 'text', 'NO'),
        ('bookings', 'plot_id', 'text', 'NO'),
        ('bookings', 'broker_id', 'text', 'NO'),
        ('bookings', 'submitted_at', 'timestamp without time zone', 'NO'),
        ('bookings', 'booked_on', 'date', 'YES'),
        ('bookings', 'sold_on', 'date', 'YES'),
        ('bookings', 'cancelled_on', 'date', 'YES'),
        ('bookings', 'registered_on', 'date', 'YES'),
        ('bookings', 'record_type', 'text', 'NO'),
        ('bookings', 'status', 'text', 'NO'),
        ('bookings', 'disc_code', 'text', 'NO'),
        ('bookings', 'price', 'numeric(18,2)', 'NO'),
        ('bookings', 'pay_plan', 'text', 'NO'),
        ('bookings', 'related_id', 'text', 'YES'),
        ('bookings', 'resolution', 'text', 'YES'),
        ('bookings', 'resolved_on', 'date', 'YES'),
        ('bookings', 'cancel_reason', 'text', 'YES'),
        ('bookings', 'comm_forfeit', 'boolean', 'NO'),
        ('booking_buyers', 'booking_id', 'text', 'NO'),
        ('booking_buyers', 'buyer_id', 'text', 'NO'),
        ('booking_buyers', 'name', 'text', 'NO'),
        ('booking_buyers', 'gender', 'text', 'NO'),
        ('booking_buyers', 'relation', 'text', 'NO'),
        ('booking_buyers', 'is_primary', 'boolean', 'NO'),
        ('payment_schedule', 'due_id', 'text', 'NO'),
        ('payment_schedule', 'booking_id', 'text', 'NO'),
        ('payment_schedule', 'component', 'text', 'NO'),
        ('payment_schedule', 'inst_no', 'integer', 'NO'),
        ('payment_schedule', 'due_on', 'date', 'NO'),
        ('payment_schedule', 'due_amt', 'numeric(18,2)', 'NO'),
        ('payments', 'pay_id', 'text', 'NO'),
        ('payments', 'txn_ref', 'text', 'NO'),
        ('payments', 'booking_id', 'text', 'NO'),
        ('payments', 'due_id', 'text', 'YES'),
        ('payments', 'charge_id', 'text', 'YES'),
        ('payments', 'txn_on', 'date', 'NO'),
        ('payments', 'component', 'text', 'NO'),
        ('payments', 'entry_type', 'text', 'NO'),
        ('payments', 'amount', 'numeric(18,2)', 'NO'),
        ('payments', 'verify_status', 'text', 'NO'),
        ('government_charges', 'charge_id', 'text', 'NO'),
        ('government_charges', 'booking_id', 'text', 'NO'),
        ('government_charges', 'charge_type', 'text', 'NO'),
        ('government_charges', 'assessed_on', 'date', 'NO'),
        ('government_charges', 'base_value', 'numeric(18,2)', 'NO'),
        ('government_charges', 'rate', 'numeric', 'YES'),
        ('government_charges', 'amount', 'numeric(18,2)', 'NO'),
        ('government_charges', 'nonrefund_amt', 'numeric(18,2)', 'NO'),
        ('government_charges', 'treatment', 'text', 'NO'),
        ('government_charges', 'basis_status', 'text', 'NO')
),
actual_columns AS (
    SELECT column_info.table_name AS tbl, column_info.column_name AS col,
           format_type(column_def.atttypid, column_def.atttypmod) AS data_type, column_info.is_nullable
    FROM information_schema.columns column_info
    JOIN pg_namespace schema_info ON schema_info.nspname = column_info.table_schema
    JOIN pg_class table_info
        ON table_info.relnamespace = schema_info.oid
       AND table_info.relname = column_info.table_name
    JOIN pg_attribute column_def
        ON column_def.attrelid = table_info.oid
       AND column_def.attname = column_info.column_name
    WHERE column_info.table_schema = 'public' AND column_info.table_name IN (SELECT tbl FROM table_counts)
),
-- 4. Check that the required primary, unique and foreign keys exist.
expected_keys(tbl, cols, kind) AS (
    VALUES ('plots', ARRAY['plot_id'], 'p'),
           ('brokers', ARRAY['broker_id'], 'p'),
           ('bookings', ARRAY['booking_id'], 'p'),
           ('booking_buyers', ARRAY['booking_id', 'buyer_id'], 'p'),
           ('payment_schedule', ARRAY['due_id'], 'p'),
           ('government_charges', ARRAY['charge_id'], 'p'),
           ('payments', ARRAY['pay_id'], 'p'),
           ('plots', ARRAY['zone', 'block', 'plot_no'], 'u'),
           ('payment_schedule', ARRAY['due_id', 'booking_id'], 'u'),
           ('government_charges', ARRAY['charge_id', 'booking_id'], 'u')
),
expected_fks(tbl, cols, ref_tbl, ref_cols) AS (
    VALUES ('bookings', ARRAY['plot_id'], 'plots', ARRAY['plot_id']),
           ('bookings', ARRAY['broker_id'], 'brokers', ARRAY['broker_id']),
           ('booking_buyers', ARRAY['booking_id'], 'bookings', ARRAY['booking_id']),
           ('payment_schedule', ARRAY['booking_id'], 'bookings', ARRAY['booking_id']),
           ('government_charges', ARRAY['booking_id'], 'bookings', ARRAY['booking_id']),
           ('payments', ARRAY['booking_id'], 'bookings', ARRAY['booking_id']),
           ('payments', ARRAY['due_id', 'booking_id'], 'payment_schedule', ARRAY['due_id', 'booking_id']),
           ('payments', ARRAY['charge_id', 'booking_id'], 'government_charges', ARRAY['charge_id', 'booking_id'])
),
actual_constraints AS (
    -- Resolve catalog column numbers to names in key order. Order matters for
    -- composite keys: checking constraint names alone would miss a different key.
    SELECT table_info.relname AS tbl, constraint_info.contype::text AS kind, constraint_info.convalidated,
           constraint_info.condeferrable, constraint_info.confdeltype, constraint_info.confupdtype,
           ARRAY(
               SELECT column_def.attname::text
               FROM unnest(constraint_info.conkey) WITH ORDINALITY key_column(column_num, position)
               JOIN pg_attribute column_def
                   ON column_def.attrelid = constraint_info.conrelid
                  AND column_def.attnum = key_column.column_num
               ORDER BY key_column.position
           ) AS cols,
           ref_table.relname AS ref_tbl, ref_schema.nspname AS ref_schema,
           ARRAY(
               SELECT column_def.attname::text
               FROM unnest(constraint_info.confkey) WITH ORDINALITY key_column(column_num, position)
               JOIN pg_attribute column_def
                   ON column_def.attrelid = constraint_info.confrelid
                  AND column_def.attnum = key_column.column_num
               ORDER BY key_column.position
           ) AS ref_cols
    FROM pg_constraint constraint_info
    JOIN pg_class table_info ON table_info.oid = constraint_info.conrelid
    JOIN pg_namespace schema_info ON schema_info.oid = table_info.relnamespace
    LEFT JOIN pg_class ref_table ON ref_table.oid = constraint_info.confrelid
    LEFT JOIN pg_namespace ref_schema ON ref_schema.oid = ref_table.relnamespace
    WHERE schema_info.nspname = 'public' AND table_info.relname IN (SELECT tbl FROM table_counts)
),
-- 5. Find orphan rows, including when a foreign key is missing.
relationship_errors(check_name, failures) AS (
    SELECT 'booking_plot', COUNT(*)
    FROM public.bookings b
    LEFT JOIN public.plots p ON p.plot_id = b.plot_id
    WHERE p.plot_id IS NULL
    UNION ALL
    SELECT 'booking_broker', COUNT(*)
    FROM public.bookings b
    LEFT JOIN public.brokers r ON r.broker_id = b.broker_id
    WHERE r.broker_id IS NULL
    UNION ALL
    SELECT 'buyer_booking', COUNT(*)
    FROM public.booking_buyers x
    LEFT JOIN public.bookings b ON b.booking_id = x.booking_id
    WHERE b.booking_id IS NULL
    UNION ALL
    SELECT 'schedule_booking', COUNT(*)
    FROM public.payment_schedule x
    LEFT JOIN public.bookings b ON b.booking_id = x.booking_id
    WHERE b.booking_id IS NULL
    UNION ALL
    SELECT 'charge_booking', COUNT(*)
    FROM public.government_charges x
    LEFT JOIN public.bookings b ON b.booking_id = x.booking_id
    WHERE b.booking_id IS NULL
    UNION ALL
    SELECT 'payment_booking', COUNT(*)
    FROM public.payments x
    LEFT JOIN public.bookings b ON b.booking_id = x.booking_id
    WHERE b.booking_id IS NULL
    UNION ALL
    SELECT 'payment_due_same_booking', COUNT(*)
    FROM public.payments p
    LEFT JOIN public.payment_schedule s ON s.due_id = p.due_id AND s.booking_id = p.booking_id
    WHERE p.due_id IS NOT NULL AND s.due_id IS NULL
    UNION ALL
    SELECT 'payment_charge_same_booking', COUNT(*)
    FROM public.payments p
    LEFT JOIN public.government_charges g ON g.charge_id = p.charge_id AND g.booking_id = p.booking_id
    WHERE p.charge_id IS NOT NULL AND g.charge_id IS NULL
    UNION ALL
    SELECT 'related_booking', COUNT(*)
    FROM public.bookings b
    LEFT JOIN public.bookings r ON r.booking_id = b.related_id
    WHERE b.related_id IS NOT NULL AND r.booking_id IS NULL
),
-- 6. Check buyer counts, booking protection and permitted dates.
quality_errors(check_name, failures) AS (
    SELECT 'rejected_with_financial_records', COUNT(*)
    FROM public.bookings b
    WHERE b.record_type = 'REJECTED_ATTEMPT' AND (
        EXISTS (SELECT 1 FROM public.payment_schedule s WHERE s.booking_id = b.booking_id)
        OR EXISTS (SELECT 1 FROM public.government_charges g WHERE g.booking_id = b.booking_id)
        OR EXISTS (SELECT 1 FROM public.payments p WHERE p.booking_id = b.booking_id)
    )
    UNION ALL
    SELECT 'buyer_count_or_primary', COUNT(*)
    FROM (
        SELECT b.booking_id
        FROM public.bookings b
        LEFT JOIN public.booking_buyers bb ON bb.booking_id = b.booking_id
        GROUP BY b.booking_id
        HAVING COUNT(bb.buyer_id) NOT BETWEEN 1 AND 3
            OR COUNT(*) FILTER (WHERE bb.is_primary) <> 1
    ) invalid_buyers
    UNION ALL
    SELECT 'multiple_active_accepted', COUNT(*)
    FROM (
        SELECT plot_id
        FROM public.bookings
        WHERE record_type = 'ACCEPTED' AND status IN ('Booked', 'Sold')
        GROUP BY plot_id
        HAVING COUNT(*) > 1
    ) conflicting_active
    UNION ALL
    SELECT 'open_claim_unprotected', COUNT(*)
    FROM public.bookings b
    JOIN public.plots p ON p.plot_id = b.plot_id
    WHERE b.status = 'ClaimOpen' AND p.status <> 'Blocked'
    UNION ALL
    SELECT 'zone_area_mismatch', COUNT(*)
    FROM public.plots
    WHERE zone <> 'Z' || area_gaj::text
    UNION ALL
    SELECT 'booking_period', COUNT(*)
    FROM public.bookings
    WHERE submitted_at < TIMESTAMP '2025-04-01 00:00:00'
       OR submitted_at >= TIMESTAMP '2026-10-01 00:00:00'
    UNION ALL
    SELECT 'payment_period', COUNT(*)
    FROM public.payments
    WHERE txn_on NOT BETWEEN DATE '2025-04-01' AND DATE '2026-09-30'
    UNION ALL
    SELECT 'assessment_period', COUNT(*)
    FROM public.government_charges
    WHERE assessed_on NOT BETWEEN DATE '2025-04-01' AND DATE '2026-09-30'
),
-- 7. Assemble one result per check. FULL JOIN also exposes unexpected data.
checks AS (
    SELECT 'count:' || tbl AS check_name, expected::text AS expected,
           actual::text AS actual, actual = expected AS passed
    FROM table_counts
    UNION ALL
    SELECT 'money:' || control, expected::text, actual::text, actual = expected
    FROM money_totals
    UNION ALL
    SELECT 'ledger:' || COALESCE(expected_row.component, actual_row.component) || ':' ||
        COALESCE(expected_row.entry_type, actual_row.entry_type) || ':' || COALESCE(expected_row.verify_status, actual_row.verify_status),
        COALESCE(expected_row.row_count::text || ' rows; ' || expected_row.amount::text, 'absent'),
        COALESCE(actual_row.row_count::text || ' rows; ' || actual_row.amount::text, 'absent'),
        COALESCE(expected_row.row_count = actual_row.row_count AND expected_row.amount = actual_row.amount, false)
    FROM expected_ledger expected_row
    FULL JOIN actual_ledger actual_row USING (component, entry_type, verify_status)
    UNION ALL
    SELECT 'column:' || COALESCE(expected_row.tbl, actual_row.tbl) || '.' || COALESCE(expected_row.col, actual_row.col),
        COALESCE(expected_row.data_type || '; nullable=' || expected_row.is_nullable, 'absent'),
        COALESCE(actual_row.data_type || '; nullable=' || actual_row.is_nullable, 'absent'),
        COALESCE(expected_row.data_type = actual_row.data_type AND expected_row.is_nullable = actual_row.is_nullable, false)
    FROM expected_columns expected_row
    FULL JOIN actual_columns actual_row USING (tbl, col)
    -- LEFT JOIN retains missing keys. GROUP BY keeps one check per expected
    -- key even if the database contains several equivalent constraints.
    UNION ALL
    SELECT 'key:' || expected_row.tbl || ':' || array_to_string(expected_row.cols, ','),
        CASE expected_row.kind WHEN 'p' THEN 'primary key' ELSE 'unique constraint' END,
        CASE WHEN COUNT(actual_row.tbl) > 0 THEN 'present' ELSE 'missing or different' END,
        COUNT(actual_row.tbl) > 0
    FROM expected_keys expected_row
    LEFT JOIN actual_constraints actual_row
        ON actual_row.tbl = expected_row.tbl
        AND actual_row.cols = expected_row.cols
        AND actual_row.kind = expected_row.kind
        AND actual_row.convalidated AND NOT actual_row.condeferrable
    GROUP BY expected_row.tbl, expected_row.cols, expected_row.kind
    UNION ALL
    SELECT 'foreign_key:' || expected_row.tbl || ':' || array_to_string(expected_row.cols, ','),
        expected_row.ref_tbl || '(' || array_to_string(expected_row.ref_cols, ',') || ')',
        CASE WHEN COUNT(actual_row.tbl) > 0 THEN 'present' ELSE 'missing or different' END,
        COUNT(actual_row.tbl) > 0
    FROM expected_fks expected_row
    LEFT JOIN actual_constraints actual_row
        ON actual_row.tbl = expected_row.tbl
        AND actual_row.cols = expected_row.cols
        AND actual_row.kind = 'f'
        AND actual_row.ref_schema = 'public'
        AND actual_row.ref_tbl = expected_row.ref_tbl
        AND actual_row.ref_cols = expected_row.ref_cols
        AND actual_row.convalidated AND NOT actual_row.condeferrable
        AND actual_row.confdeltype = 'a' AND actual_row.confupdtype = 'a'
    GROUP BY expected_row.tbl, expected_row.cols, expected_row.ref_tbl, expected_row.ref_cols
    UNION ALL
    SELECT 'relationship:' || check_name, '0', failures::text, failures = 0
    FROM relationship_errors
    UNION ALL
    SELECT 'quality:' || check_name, '0', failures::text, failures = 0
    FROM quality_errors
),
-- 8. Return the summary followed by failed checks only.
result AS (
    SELECT 'SUMMARY'::text AS check_name, 'all checks pass'::text AS expected,
        COUNT(*)::text || ' checks; ' || COUNT(*) FILTER (WHERE NOT passed)::text || ' failed' AS actual,
        BOOL_AND(passed) AS passed,
        CASE
            WHEN BOOL_AND(passed) THEN 'PASS'
            WHEN NOT EXISTS (SELECT 1 FROM table_counts WHERE actual <> 0)
                THEN 'NOT_LOADED'
            ELSE 'FAIL'
        END AS status,
        CASE
            WHEN BOOL_AND(passed)
                THEN 'Run 03_add_booking_relation.sql, then test a controlled rerun.'
            WHEN NOT EXISTS (SELECT 1 FROM table_counts WHERE actual <> 0)
                THEN 'Run pl_load_suryavan in ADF, then rerun this file.'
            ELSE 'Inspect the failed rows; check ADF mappings and load completion.'
        END AS next_action
    FROM checks
    UNION ALL
    SELECT check_name, expected, actual, passed, 'FAIL',
        'Compare the expected and actual values after the ADF load.'
    FROM checks
    WHERE NOT passed
)
SELECT check_name, expected, actual, passed, status, next_action
FROM result
ORDER BY (check_name <> 'SUMMARY'), check_name;

COMMIT;
