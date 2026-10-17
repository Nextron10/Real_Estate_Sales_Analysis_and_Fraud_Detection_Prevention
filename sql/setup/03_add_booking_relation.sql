-- Phase 1 step 3: run only after 02 reports all checks passed.
-- Deferred until the full import because claims/replacements can refer forward.
-- This script does not create live booking protection or delete any records.
-- Before ADF loading, the "complete ingestion first" error is intentional.
BEGIN;
DO $relation$
DECLARE
    constraint_matches boolean;
BEGIN
    IF current_database() <> 'suryavan' THEN
        RAISE EXCEPTION 'Connect to suryavan before adding the relationship.';
    END IF;
    IF (SELECT COUNT(*) FROM public.bookings) <> 1540 THEN
        RAISE EXCEPTION 'Expected all 1540 source booking rows; complete ingestion first.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.bookings b
        LEFT JOIN public.bookings r ON r.booking_id = b.related_id
        WHERE b.related_id IS NOT NULL AND r.booking_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Missing related booking IDs; validate and correct the load first.';
    END IF;
    -- Read the named constraint once and check its columns and behaviour.
    -- LEFT JOIN keeps a mismatched constraint visible if a column is missing.
    SELECT COALESCE(
        k.contype = 'f'
        AND k.confrelid = k.conrelid
        AND k.convalidated AND NOT k.condeferrable
        AND k.confdeltype = 'a' AND k.confupdtype = 'a'
        AND k.conkey = ARRAY[source_col.attnum]
        AND k.confkey = ARRAY[target_col.attnum], false)
    INTO constraint_matches
    FROM pg_constraint k
    LEFT JOIN pg_attribute source_col
        ON source_col.attrelid = k.conrelid AND source_col.attname = 'related_id'
    LEFT JOIN pg_attribute target_col
        ON target_col.attrelid = k.conrelid AND target_col.attname = 'booking_id'
    WHERE k.conname = 'fk_bookings_related'
      AND k.conrelid = 'public.bookings'::regclass;

    -- FOUND reports whether the SELECT above returned a constraint.
    IF NOT FOUND THEN
        ALTER TABLE public.bookings ADD CONSTRAINT fk_bookings_related
            FOREIGN KEY (related_id) REFERENCES public.bookings (booking_id);
    ELSIF NOT constraint_matches THEN
        RAISE EXCEPTION 'A different constraint already uses fk_bookings_related; inspect it.';
    ELSE
        RAISE NOTICE 'The related-booking constraint already exists.';
    END IF;
END;
$relation$;
COMMIT;

SELECT conname,
       pg_get_constraintdef(oid) AS definition,
       convalidated AS validated
FROM pg_constraint
WHERE conname = 'fk_bookings_related'
  AND conrelid = 'public.bookings'::regclass;
