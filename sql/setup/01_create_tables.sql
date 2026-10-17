-- Phase 1 step 1: execute this whole file once, connected to suryavan.
-- BEGIN/COMMIT make the seven CREATE TABLE statements one transaction.
-- No DROP or TRUNCATE is used. Existing project tables cause a clear error.
-- If execution leaves your session in a failed transaction, run ROLLBACK.
BEGIN;

DO $guard$
BEGIN
    IF current_database() <> 'suryavan' THEN
        RAISE EXCEPTION 'Connect to suryavan before running this script.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name IN (
              'plots', 'brokers', 'bookings', 'booking_buyers',
              'payment_schedule', 'government_charges', 'payments'
          )
    ) THEN
        RAISE EXCEPTION 'Project tables already exist. Do not recreate them; inspect and validate the existing structure.';
    END IF;
END;
$guard$;

-- Grain: one permanent plot. Zone/block/plot number together are unique.
CREATE TABLE public.plots (
    plot_id text PRIMARY KEY,
    zone text NOT NULL CHECK (zone IN ('Z200', 'Z400', 'Z500')),
    block text NOT NULL,
    plot_no integer NOT NULL CHECK (plot_no BETWEEN 1 AND 100),
    area_gaj integer NOT NULL CHECK (area_gaj IN (200, 400, 500)),
    is_corner boolean NOT NULL,
    status text NOT NULL CHECK (status IN ('Available', 'Booked', 'Sold', 'Blocked')),
    block_reason text CHECK (block_reason IN ('UNRESOLVED_CLAIM')),
    UNIQUE (zone, block, plot_no)
);

-- Grain: one broker. IDs use text to preserve the workbook's prefixes.
CREATE TABLE public.brokers (
    broker_id text PRIMARY KEY,
    name text NOT NULL,
    joined_on date NOT NULL,
    is_active boolean NOT NULL
);

-- Grain: one accepted booking, historical claim or rejected request.
-- plot_id is NOT unique here: history can contain many requests for a plot.
-- Optional lifecycle dates remain NULL when that event did not happen.
-- submitted_at preserves the workbook's India-local time, without UTC conversion.
CREATE TABLE public.bookings (
    booking_id text PRIMARY KEY,
    plot_id text NOT NULL REFERENCES public.plots (plot_id),
    broker_id text NOT NULL REFERENCES public.brokers (broker_id),
    submitted_at timestamp without time zone NOT NULL,
    booked_on date,
    sold_on date,
    cancelled_on date,
    registered_on date,
    record_type text NOT NULL CHECK (record_type IN (
        'ACCEPTED', 'HISTORICAL_CLAIM', 'REJECTED_ATTEMPT'
    )),
    status text NOT NULL CHECK (status IN (
        'Booked', 'Sold', 'Cancelled', 'ClaimOpen', 'ClaimResolved', 'Rejected'
    )),
    disc_code text NOT NULL CHECK (disc_code IN ('NONE', 'FAMILY5', 'CONTACT3', 'COMP2')),
    price numeric(18,2) NOT NULL CHECK (price >= 0 AND price <> 'NaN'::numeric),
    pay_plan text NOT NULL CHECK (pay_plan IN ('IMMEDIATE', 'M3', 'M4', 'M6')),
    related_id text,
    resolution text CHECK (resolution IN (
        'OPEN', 'KEEP_ORIGINAL', 'NORMAL_CANCEL', 'REFUND_APPROVED',
        'REPLACEMENT_APPROVED', 'REPLACEMENT', 'BLOCKED_ATTEMPT'
    )),
    resolved_on date,
    cancel_reason text CHECK (cancel_reason IN ('BUYER_REQUEST')),
    comm_forfeit boolean NOT NULL
);

-- Grain: one buyer on one request. A buyer can recur on a replacement booking.
-- Therefore the primary key combines booking_id AND buyer_id.
CREATE TABLE public.booking_buyers (
    booking_id text NOT NULL REFERENCES public.bookings (booking_id),
    buyer_id text NOT NULL,
    name text NOT NULL,
    gender text NOT NULL CHECK (gender IN ('M', 'F')),
    relation text NOT NULL CHECK (relation IN ('FAMILY', 'CONTACT', 'OTHER')),
    is_primary boolean NOT NULL,
    PRIMARY KEY (booking_id, buyer_id)
);

-- Grain: one scheduled obligation, not an actual receipt.
CREATE TABLE public.payment_schedule (
    due_id text PRIMARY KEY,
    booking_id text NOT NULL REFERENCES public.bookings (booking_id),
    component text NOT NULL CHECK (component IN ('PLOT', 'GOVT', 'LATE_FEE')),
    inst_no integer NOT NULL CHECK (inst_no >= 0),
    due_on date NOT NULL,
    due_amt numeric(18,2) NOT NULL CHECK (due_amt >= 0 AND due_amt <> 'NaN'::numeric),
    UNIQUE (due_id, booking_id)
);

-- Grain: one assessed government-charge component.
-- Rates are fractions (0.02 = 2%). Unconstrained numeric avoids a fixed scale.
-- A fixed fee can have rate=NULL. Amounts remain exact two-decimal rupees.
CREATE TABLE public.government_charges (
    charge_id text PRIMARY KEY,
    booking_id text NOT NULL REFERENCES public.bookings (booking_id),
    charge_type text NOT NULL CHECK (charge_type IN (
        'STAMP_DUTY', 'GRAM_SURCHARGE', 'REG_FEE', 'TDS'
    )),
    assessed_on date NOT NULL,
    base_value numeric(18,2) NOT NULL CHECK (base_value >= 0 AND base_value <> 'NaN'::numeric),
    rate numeric CHECK (rate BETWEEN 0 AND 1),
    amount numeric(18,2) NOT NULL CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    nonrefund_amt numeric(18,2) NOT NULL CHECK (nonrefund_amt >= 0 AND nonrefund_amt <> 'NaN'::numeric),
    treatment text NOT NULL CHECK (treatment IN ('PASS_THROUGH', 'WITHHOLDING_CREDIT')),
    basis_status text NOT NULL CHECK (basis_status IN ('Provisional', 'Illustrative')),
    UNIQUE (charge_id, booking_id),
    CHECK (nonrefund_amt <= amount)
);

-- Grain: one ledger movement/allocation. txn_ref can group several rows.
-- A positive amount's direction and cash/noncash meaning come from entry_type.
-- Composite foreign keys ensure due/charge references belong to this booking.
CREATE TABLE public.payments (
    pay_id text PRIMARY KEY,
    txn_ref text NOT NULL,
    booking_id text NOT NULL REFERENCES public.bookings (booking_id),
    due_id text,
    charge_id text,
    txn_on date NOT NULL,
    component text NOT NULL CHECK (component IN ('PLOT', 'GOVT', 'LATE_FEE', 'COMMISSION')),
    entry_type text NOT NULL CHECK (entry_type IN (
        'RECEIPT', 'REFUND', 'REMITTANCE', 'TDS_CREDIT', 'TRANSFER_IN',
        'TRANSFER_OUT', 'COMMISSION_PAID', 'COMMISSION_RECOVERED',
        'OFFSET_RECOVERY', 'OFFSET_WITHHELD'
    )),
    amount numeric(18,2) NOT NULL CHECK (amount >= 0 AND amount <> 'NaN'::numeric),
    verify_status text NOT NULL CHECK (verify_status IN ('Verified', 'Pending', 'Rejected')),
    FOREIGN KEY (due_id, booking_id)
        REFERENCES public.payment_schedule (due_id, booking_id),
    FOREIGN KEY (charge_id, booking_id)
        REFERENCES public.government_charges (charge_id, booking_id)
);

-- The related_id self-reference is added by 03 only after the full load.
-- Operational double-booking prevention is a later stage, not implemented here.
COMMIT;

-- CREATE TABLE returns command messages rather than business records.
-- This read-only result confirms the seven table definitions are present.
-- It does not load the workbook; the next step is the ADF Copy pipeline.
SELECT table_name, COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'plots', 'brokers', 'bookings', 'booking_buyers',
      'payment_schedule', 'government_charges', 'payments'
  )
GROUP BY table_name
ORDER BY table_name;
