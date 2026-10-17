-- Phase 1 step 4: run once before the rerun and once after it.
-- Save both result sets. Every table's count AND fingerprint must be identical.
-- JSONB represents all column values; STRING_AGG uses deterministic PK ordering.
-- MD5 is used as a change detector, not as a credential/security mechanism.
-- This query is read-only and creates no extra tables or extensions.
-- Run after 02 passes. Empty tables also have fingerprints; zero-row results
-- do not establish that ADF loading or source validation has succeeded.
BEGIN TRANSACTION READ ONLY;
DO $guard$
BEGIN
    IF current_database() <> 'suryavan' THEN
        RAISE EXCEPTION 'Connect to suryavan before capturing the rerun state.';
    END IF;
END;
$guard$;
SET LOCAL DateStyle TO 'ISO, YMD';
SELECT 'plots' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.plot_id), '')) AS fingerprint
FROM public.plots t
UNION ALL
SELECT 'brokers' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.broker_id), '')) AS fingerprint
FROM public.brokers t
UNION ALL
SELECT 'bookings' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.booking_id), '')) AS fingerprint
FROM public.bookings t
UNION ALL
SELECT 'booking_buyers' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.booking_id, t.buyer_id), '')) AS fingerprint
FROM public.booking_buyers t
UNION ALL
SELECT 'payment_schedule' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.due_id), '')) AS fingerprint
FROM public.payment_schedule t
UNION ALL
SELECT 'government_charges' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.charge_id), '')) AS fingerprint
FROM public.government_charges t
UNION ALL
SELECT 'payments' AS table_name, COUNT(*) AS row_count,
       MD5(COALESCE(STRING_AGG(TO_JSONB(t)::text, E'\n' ORDER BY t.pay_id), '')) AS fingerprint
FROM public.payments t
ORDER BY table_name;
COMMIT;
