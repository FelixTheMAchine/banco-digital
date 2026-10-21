SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: protect_account_identity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_account_identity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.user_id <> OLD.user_id OR NEW.number <> OLD.number OR NEW.branch <> OLD.branch THEN
    RAISE EXCEPTION 'account ownership and identifiers are immutable';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: reject_audit_log_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_audit_log_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs are append-only';
END;
$$;


--
-- Name: reject_ledger_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_ledger_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'ledger records are immutable; use a compensating transaction';
END;
$$;


--
-- Name: validate_account_ledger_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_account_ledger_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  target_id uuid;
  ledger_total numeric;
  cached_total numeric;
BEGIN
  IF TG_TABLE_NAME = 'accounts' THEN
    target_id := NEW.id;
    IF TG_OP = 'UPDATE' AND NEW.available_cents = OLD.available_cents AND NEW.blocked_cents = OLD.blocked_cents THEN
  RETURN NEW;
END IF;

  ELSE
    SELECT account_id INTO target_id FROM ledger_accounts WHERE id = NEW.ledger_account_id;
  END IF;
  IF target_id IS NULL THEN RETURN NEW; END IF;
  SELECT available_cents::numeric + blocked_cents::numeric INTO cached_total FROM accounts WHERE id = target_id;
  SELECT COALESCE(sum(CASE WHEN e.direction = 'credit' THEN e.amount_cents ELSE -e.amount_cents END), 0)
    INTO ledger_total FROM ledger_entries e JOIN ledger_accounts l ON l.id = e.ledger_account_id
    WHERE l.account_id = target_id;
  IF cached_total <> ledger_total THEN
    RAISE EXCEPTION 'account balance does not match ledger %', target_id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validate_ledger_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_ledger_balance() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  target_id uuid;
  debit_total numeric;
  credit_total numeric;
  entry_count integer;
  expected_amount bigint;
BEGIN
  IF TG_TABLE_NAME = 'ledger_transactions' THEN target_id := NEW.id;
  ELSE target_id := NEW.ledger_transaction_id; END IF;
  SELECT amount_cents INTO expected_amount FROM ledger_transactions WHERE id = target_id;
  SELECT count(*), COALESCE(sum(amount_cents) FILTER (WHERE direction = 'debit'), 0),
    COALESCE(sum(amount_cents) FILTER (WHERE direction = 'credit'), 0)
    INTO entry_count, debit_total, credit_total FROM ledger_entries WHERE ledger_transaction_id = target_id;
  IF entry_count < 2 OR debit_total <> credit_total OR debit_total <> expected_amount THEN
    RAISE EXCEPTION 'unbalanced ledger transaction %', target_id;
  END IF;
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    number character varying(20) NOT NULL,
    branch character varying(4) DEFAULT '0001'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    available_cents bigint DEFAULT 0 NOT NULL,
    blocked_cents bigint DEFAULT 0 NOT NULL,
    daily_limit_cents bigint DEFAULT 5000000 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT accounts_available_cents_bounds CHECK (((available_cents >= 0) AND (available_cents <= '9000000000000000'::bigint))),
    CONSTRAINT accounts_blocked_cents_bounds CHECK (((blocked_cents >= 0) AND (blocked_cents <= '9000000000000000'::bigint))),
    CONSTRAINT accounts_daily_limit_cents_bounds CHECK (((daily_limit_cents >= 0) AND (daily_limit_cents <= '9000000000000000'::bigint))),
    CONSTRAINT accounts_simulated_branch CHECK (((branch)::text = '0001'::text)),
    CONSTRAINT accounts_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('blocked'::character varying)::text, ('closed'::character varying)::text])))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    action character varying(100) NOT NULL,
    subject_id uuid,
    request_id character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    access_digest character varying(64) NOT NULL,
    refresh_digest character varying(64) NOT NULL,
    family_id uuid NOT NULL,
    access_expires_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    last_used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    mfa_verified_at timestamp(6) without time zone,
    CONSTRAINT sessions_access_digest_format CHECK (((access_digest)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT sessions_refresh_digest_format CHECK (((refresh_digest)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT sessions_valid_expiry CHECK ((access_expires_at <= expires_at))
);


--
-- Name: credit_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying DEFAULT 'Regras demonstrativas'::character varying NOT NULL,
    version integer NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    active boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT credit_rules_valid_config CHECK (((version > 0) AND (jsonb_typeof(config) = 'object'::text)))
);


--
-- Name: financial_goals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_goals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    name character varying(120) NOT NULL,
    target_cents bigint NOT NULL,
    target_date date NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT financial_goals_positive_target CHECK (((target_cents >= 1) AND (target_cents <= '9000000000000000'::bigint))),
    CONSTRAINT financial_goals_valid_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: financial_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.financial_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    value bigint NOT NULL,
    version bigint DEFAULT 1 NOT NULL,
    updated_by_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT financial_rule_known_key CHECK (((key)::text = ANY (ARRAY[('banking.daily_limit_cents'::character varying)::text, ('fraud.high_value_cents'::character varying)::text, ('banking.max_transaction_cents'::character varying)::text, ('fraud.attempts_per_minute'::character varying)::text, ('fraud.cooldown_seconds'::character varying)::text]))),
    CONSTRAINT financial_rule_positive_value CHECK (((value >= 1) AND (value <= '9000000000000000'::bigint))),
    CONSTRAINT financial_rule_positive_version CHECK ((version > 0))
);


--
-- Name: investment_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investment_profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    profile character varying NOT NULL,
    score integer NOT NULL,
    answers jsonb DEFAULT '{}'::jsonb NOT NULL,
    recommendations jsonb DEFAULT '[]'::jsonb NOT NULL,
    emergency_target_cents bigint NOT NULL,
    available_to_invest_cents bigint NOT NULL,
    warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT investment_profiles_json_shapes CHECK (((jsonb_typeof(answers) = 'object'::text) AND (jsonb_typeof(recommendations) = 'array'::text) AND (jsonb_typeof(warnings) = 'array'::text))),
    CONSTRAINT investment_profiles_positive_money CHECK (((emergency_target_cents >= 0) AND (available_to_invest_cents >= 0))),
    CONSTRAINT investment_profiles_valid_classification CHECK ((((profile)::text = ANY (ARRAY[('conservative'::character varying)::text, ('moderate'::character varying)::text, ('aggressive'::character varying)::text])) AND ((score >= 0) AND (score <= 100))))
);


--
-- Name: investment_simulations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.investment_simulations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    initial_amount_cents bigint NOT NULL,
    monthly_contribution_cents bigint NOT NULL,
    months integer NOT NULL,
    annual_rate_percent numeric(8,4) NOT NULL,
    final_cents bigint NOT NULL,
    contributed_cents bigint NOT NULL,
    earnings_cents bigint NOT NULL,
    projection jsonb DEFAULT '[]'::jsonb NOT NULL,
    scenarios jsonb DEFAULT '[]'::jsonb NOT NULL,
    portfolio jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT investment_simulations_input_bounds CHECK (((initial_amount_cents >= 0) AND (initial_amount_cents <= 100000000) AND ((monthly_contribution_cents >= 0) AND (monthly_contribution_cents <= 100000000)) AND ((months >= 1) AND (months <= 600)))),
    CONSTRAINT investment_simulations_result_bounds CHECK (((annual_rate_percent >= ('-20'::integer)::numeric) AND (annual_rate_percent <= (50)::numeric) AND ((final_cents >= 0) AND (final_cents <= '9000000000000000'::bigint)) AND (contributed_cents >= 0) AND (earnings_cents = (final_cents - contributed_cents))))
);


--
-- Name: ledger_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid,
    code character varying NOT NULL,
    kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_accounts_kind CHECK (((kind)::text = ANY (ARRAY[('asset'::character varying)::text, ('liability'::character varying)::text]))),
    CONSTRAINT ledger_accounts_owner CHECK (((((kind)::text = 'asset'::text) AND (account_id IS NULL)) OR (((kind)::text = 'liability'::text) AND (account_id IS NOT NULL))))
);


--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ledger_transaction_id uuid NOT NULL,
    ledger_account_id uuid NOT NULL,
    direction character varying NOT NULL,
    amount_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_entry_amount CHECK (((amount_cents >= 1) AND (amount_cents <= '9000000000000000'::bigint))),
    CONSTRAINT ledger_entry_direction CHECK (((direction)::text = ANY (ARRAY[('debit'::character varying)::text, ('credit'::character varying)::text])))
);


--
-- Name: ledger_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind character varying NOT NULL,
    amount_cents bigint NOT NULL,
    idempotency_key character varying(128) NOT NULL,
    request_digest character varying(64) NOT NULL,
    description character varying(160) DEFAULT ''::character varying NOT NULL,
    reverses_id uuid,
    completed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_request_digest CHECK (((request_digest)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT ledger_reversal_reference CHECK ((((kind)::text = 'reversal'::text) = (reverses_id IS NOT NULL))),
    CONSTRAINT ledger_transaction_amount CHECK (((amount_cents >= 1) AND (amount_cents <= '9000000000000000'::bigint))),
    CONSTRAINT ledger_transaction_kind CHECK (((kind)::text = ANY (ARRAY[('deposit'::character varying)::text, ('withdrawal'::character varying)::text, ('transfer'::character varying)::text, ('reversal'::character varying)::text])))
);


--
-- Name: loan_appeals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loan_appeals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    loan_id uuid NOT NULL,
    user_id uuid NOT NULL,
    reason character varying(2000) NOT NULL,
    status character varying DEFAULT 'pending_review'::character varying NOT NULL,
    outcome jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT appeals_valid_status CHECK (((status)::text = ANY (ARRAY[('pending_review'::character varying)::text, ('reviewed'::character varying)::text])))
);


--
-- Name: loan_installments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loan_installments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    loan_id uuid NOT NULL,
    number integer NOT NULL,
    due_date date NOT NULL,
    principal_cents bigint NOT NULL,
    interest_cents bigint NOT NULL,
    payment_cents bigint NOT NULL,
    balance_cents bigint NOT NULL,
    status character varying DEFAULT 'simulated'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT installments_valid_amounts CHECK (((number > 0) AND (principal_cents >= 0) AND (interest_cents >= 0) AND (payment_cents = (principal_cents + interest_cents)) AND (balance_cents >= 0))),
    CONSTRAINT installments_valid_status CHECK (((status)::text = ANY (ARRAY[('simulated'::character varying)::text, ('paid'::character varying)::text, ('overdue'::character varying)::text])))
);


--
-- Name: loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    amount_cents bigint NOT NULL,
    term_months integer NOT NULL,
    monthly_rate numeric(12,8) NOT NULL,
    installment_cents bigint NOT NULL,
    total_cents bigint NOT NULL,
    status character varying NOT NULL,
    eligibility_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    rule_version integer DEFAULT 0 NOT NULL,
    idempotency_key character varying(128) NOT NULL,
    request_digest character varying(64) NOT NULL,
    reviewed_by_id uuid,
    reviewed_at timestamp(6) without time zone,
    review_reason character varying(2000),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT loans_positive_money CHECK (((amount_cents >= 1) AND (amount_cents <= '9000000000000000'::bigint) AND (installment_cents > 0) AND (total_cents >= amount_cents))),
    CONSTRAINT loans_valid_status CHECK (((status)::text = ANY (ARRAY[('pending_review'::character varying)::text, ('rejected'::character varying)::text, ('approved'::character varying)::text, ('reviewed_rejected'::character varying)::text]))),
    CONSTRAINT loans_valid_terms CHECK (((term_months >= 1) AND (term_months <= 120) AND ((monthly_rate >= (0)::numeric) AND (monthly_rate <= 0.10))))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind character varying NOT NULL,
    title character varying(150) NOT NULL,
    body character varying(500) NOT NULL,
    read_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: purpose_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.purpose_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    purpose character varying NOT NULL,
    token_digest character varying(64) NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    consumed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT tokens_digest_format CHECK (((token_digest)::text ~ '^[0-9a-f]{64}$'::text)),
    CONSTRAINT tokens_valid_purpose CHECK (((purpose)::text = ANY (ARRAY[('email_verification'::character varying)::text, ('password_reset'::character varying)::text])))
);


--
-- Name: scheduled_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    source_account_id uuid NOT NULL,
    destination_account_id uuid NOT NULL,
    ledger_transaction_id uuid,
    amount_cents bigint NOT NULL,
    description character varying(160) DEFAULT ''::character varying NOT NULL,
    idempotency_key character varying(128) NOT NULL,
    request_digest character varying(64) NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    dispatch_enqueued_at timestamp(6) without time zone,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    failure_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT schedules_amount CHECK (((amount_cents >= 1) AND (amount_cents <= '9000000000000000'::bigint))),
    CONSTRAINT schedules_completed_ledger CHECK ((((status)::text = 'completed'::text) = (ledger_transaction_id IS NOT NULL))),
    CONSTRAINT schedules_distinct_accounts CHECK ((source_account_id <> destination_account_id)),
    CONSTRAINT schedules_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('completed'::character varying)::text, ('cancelled'::character varying)::text, ('failed'::character varying)::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: security_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.security_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    account_id uuid,
    kind character varying NOT NULL,
    severity character varying DEFAULT 'medium'::character varying NOT NULL,
    reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    reviewed_by_id uuid,
    reviewed_at timestamp(6) without time zone,
    review_reason character varying(500),
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT security_event_reasons CHECK ((jsonb_typeof(reasons) = 'array'::text)),
    CONSTRAINT security_event_severity CHECK (((severity)::text = ANY (ARRAY[('low'::character varying)::text, ('medium'::character varying)::text, ('high'::character varying)::text]))),
    CONSTRAINT security_event_status CHECK (((status)::text = ANY (ARRAY[('open'::character varying)::text, ('reviewed'::character varying)::text])))
);


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ledger_transaction_id uuid NOT NULL,
    source_account_id uuid NOT NULL,
    destination_account_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT transfers_distinct_accounts CHECK ((source_account_id <> destination_account_id))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    full_name character varying(150) NOT NULL,
    cpf character varying(11) NOT NULL,
    birth_date date NOT NULL,
    email character varying(254) NOT NULL,
    phone character varying(16) NOT NULL,
    address jsonb NOT NULL,
    profession character varying(120) NOT NULL,
    monthly_salary_cents bigint DEFAULT 0 NOT NULL,
    other_income_cents bigint DEFAULT 0 NOT NULL,
    monthly_expenses_cents bigint DEFAULT 0 NOT NULL,
    existing_debts_cents bigint DEFAULT 0 NOT NULL,
    investor_profile character varying DEFAULT 'not_assessed'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    role character varying DEFAULT 'customer'::character varying NOT NULL,
    password_digest character varying NOT NULL,
    email_verified_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    mfa_secret text,
    mfa_pending_secret text,
    mfa_enabled_at timestamp(6) without time zone,
    mfa_pending_expires_at timestamp(6) without time zone,
    mfa_last_otp_at bigint,
    mfa_recovery_digests jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT users_address_object CHECK ((jsonb_typeof(address) = 'object'::text)),
    CONSTRAINT users_argon2id_password CHECK (((password_digest)::text ~~ '$argon2id$%'::text)),
    CONSTRAINT users_cpf_format CHECK (((cpf)::text ~ '^[0-9]{11}$'::text)),
    CONSTRAINT users_existing_debts_cents_bounds CHECK (((existing_debts_cents >= 0) AND (existing_debts_cents <= '9000000000000000'::bigint))),
    CONSTRAINT users_investor_profile CHECK (((investor_profile)::text = ANY (ARRAY[('not_assessed'::character varying)::text, ('conservative'::character varying)::text, ('moderate'::character varying)::text, ('aggressive'::character varying)::text]))),
    CONSTRAINT users_mfa_enabled_secret CHECK (((mfa_enabled_at IS NULL) OR (mfa_secret IS NOT NULL))),
    CONSTRAINT users_mfa_pending_expiry CHECK (((mfa_pending_secret IS NULL) = (mfa_pending_expires_at IS NULL))),
    CONSTRAINT users_mfa_positive_step CHECK (((mfa_last_otp_at IS NULL) OR (mfa_last_otp_at >= 0))),
    CONSTRAINT users_mfa_recovery_array CHECK (((jsonb_typeof(mfa_recovery_digests) = 'array'::text) AND (jsonb_array_length(mfa_recovery_digests) <= 8))),
    CONSTRAINT users_monthly_expenses_cents_bounds CHECK (((monthly_expenses_cents >= 0) AND (monthly_expenses_cents <= '9000000000000000'::bigint))),
    CONSTRAINT users_monthly_salary_cents_bounds CHECK (((monthly_salary_cents >= 0) AND (monthly_salary_cents <= '9000000000000000'::bigint))),
    CONSTRAINT users_normalized_email CHECK (((email)::text = lower(TRIM(BOTH FROM email)))),
    CONSTRAINT users_other_income_cents_bounds CHECK (((other_income_cents >= 0) AND (other_income_cents <= '9000000000000000'::bigint))),
    CONSTRAINT users_role CHECK (((role)::text = ANY (ARRAY[('customer'::character varying)::text, ('admin'::character varying)::text]))),
    CONSTRAINT users_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('blocked'::character varying)::text, ('deactivated'::character varying)::text])))
);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_pkey PRIMARY KEY (id);


--
-- Name: credit_rules credit_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_rules
    ADD CONSTRAINT credit_rules_pkey PRIMARY KEY (id);


--
-- Name: financial_goals financial_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_goals
    ADD CONSTRAINT financial_goals_pkey PRIMARY KEY (id);


--
-- Name: financial_rules financial_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_rules
    ADD CONSTRAINT financial_rules_pkey PRIMARY KEY (id);


--
-- Name: investment_profiles investment_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investment_profiles
    ADD CONSTRAINT investment_profiles_pkey PRIMARY KEY (id);


--
-- Name: investment_simulations investment_simulations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investment_simulations
    ADD CONSTRAINT investment_simulations_pkey PRIMARY KEY (id);


--
-- Name: ledger_accounts ledger_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts
    ADD CONSTRAINT ledger_accounts_pkey PRIMARY KEY (id);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: ledger_transactions ledger_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions
    ADD CONSTRAINT ledger_transactions_pkey PRIMARY KEY (id);


--
-- Name: loan_appeals loan_appeals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_appeals
    ADD CONSTRAINT loan_appeals_pkey PRIMARY KEY (id);


--
-- Name: loan_installments loan_installments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_pkey PRIMARY KEY (id);


--
-- Name: loans loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: purpose_tokens purpose_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purpose_tokens
    ADD CONSTRAINT purpose_tokens_pkey PRIMARY KEY (id);


--
-- Name: scheduled_transfers scheduled_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_transfers
    ADD CONSTRAINT scheduled_transfers_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: security_events security_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_events
    ADD CONSTRAINT security_events_pkey PRIMARY KEY (id);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_accounts_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_number ON public.accounts USING btree (number);


--
-- Name: index_accounts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_accounts_on_user_id ON public.accounts USING btree (user_id);


--
-- Name: index_audit_logs_on_action_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_action_and_created_at ON public.audit_logs USING btree (action, created_at);


--
-- Name: index_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_created_at ON public.audit_logs USING btree (created_at);


--
-- Name: index_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: index_auth_sessions_on_access_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_auth_sessions_on_access_digest ON public.auth_sessions USING btree (access_digest);


--
-- Name: index_auth_sessions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_sessions_on_expires_at ON public.auth_sessions USING btree (expires_at);


--
-- Name: index_auth_sessions_on_family_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_sessions_on_family_id ON public.auth_sessions USING btree (family_id);


--
-- Name: index_auth_sessions_on_refresh_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_auth_sessions_on_refresh_digest ON public.auth_sessions USING btree (refresh_digest);


--
-- Name: index_auth_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_sessions_on_user_id ON public.auth_sessions USING btree (user_id);


--
-- Name: index_credit_rules_on_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_credit_rules_on_version ON public.credit_rules USING btree (version);


--
-- Name: index_financial_goals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_financial_goals_on_user_id ON public.financial_goals USING btree (user_id);


--
-- Name: index_financial_rules_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_financial_rules_on_key ON public.financial_rules USING btree (key);


--
-- Name: index_financial_rules_on_updated_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_financial_rules_on_updated_by_id ON public.financial_rules USING btree (updated_by_id);


--
-- Name: index_investment_profiles_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_investment_profiles_on_user_id ON public.investment_profiles USING btree (user_id);


--
-- Name: index_investment_simulations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_investment_simulations_on_user_id ON public.investment_simulations USING btree (user_id);


--
-- Name: index_ledger_accounts_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_accounts_on_account_id ON public.ledger_accounts USING btree (account_id);


--
-- Name: index_ledger_accounts_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_accounts_on_code ON public.ledger_accounts USING btree (code);


--
-- Name: index_ledger_entries_on_ledger_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_ledger_account_id ON public.ledger_entries USING btree (ledger_account_id);


--
-- Name: index_ledger_transactions_on_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_transactions_on_completed_at ON public.ledger_transactions USING btree (completed_at);


--
-- Name: index_ledger_transactions_on_reverses_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ledger_transactions_on_reverses_id ON public.ledger_transactions USING btree (reverses_id);


--
-- Name: index_ledger_transactions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_transactions_on_user_id ON public.ledger_transactions USING btree (user_id);


--
-- Name: index_loan_appeals_on_loan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loan_appeals_on_loan_id ON public.loan_appeals USING btree (loan_id);


--
-- Name: index_loan_appeals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loan_appeals_on_user_id ON public.loan_appeals USING btree (user_id);


--
-- Name: index_loan_installments_on_loan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loan_installments_on_loan_id ON public.loan_installments USING btree (loan_id);


--
-- Name: index_loan_installments_on_loan_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_loan_installments_on_loan_id_and_number ON public.loan_installments USING btree (loan_id, number);


--
-- Name: index_loans_on_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loans_on_reviewed_by_id ON public.loans USING btree (reviewed_by_id);


--
-- Name: index_loans_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loans_on_status_and_created_at ON public.loans USING btree (status, created_at);


--
-- Name: index_loans_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_loans_on_user_id ON public.loans USING btree (user_id);


--
-- Name: index_loans_on_user_id_and_idempotency_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_loans_on_user_id_and_idempotency_key ON public.loans USING btree (user_id, idempotency_key);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_notifications_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id_and_created_at ON public.notifications USING btree (user_id, created_at);


--
-- Name: index_purpose_tokens_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purpose_tokens_on_expires_at ON public.purpose_tokens USING btree (expires_at);


--
-- Name: index_purpose_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_purpose_tokens_on_token_digest ON public.purpose_tokens USING btree (token_digest);


--
-- Name: index_purpose_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purpose_tokens_on_user_id ON public.purpose_tokens USING btree (user_id);


--
-- Name: index_purpose_tokens_on_user_id_and_purpose; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_purpose_tokens_on_user_id_and_purpose ON public.purpose_tokens USING btree (user_id, purpose);


--
-- Name: index_scheduled_transfers_on_destination_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_transfers_on_destination_account_id ON public.scheduled_transfers USING btree (destination_account_id);


--
-- Name: index_scheduled_transfers_on_ledger_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scheduled_transfers_on_ledger_transaction_id ON public.scheduled_transfers USING btree (ledger_transaction_id);


--
-- Name: index_scheduled_transfers_on_source_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_transfers_on_source_account_id ON public.scheduled_transfers USING btree (source_account_id);


--
-- Name: index_scheduled_transfers_on_status_and_scheduled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_transfers_on_status_and_scheduled_at ON public.scheduled_transfers USING btree (status, scheduled_at);


--
-- Name: index_scheduled_transfers_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_transfers_on_user_id ON public.scheduled_transfers USING btree (user_id);


--
-- Name: index_security_events_on_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_security_events_on_account_id ON public.security_events USING btree (account_id);


--
-- Name: index_security_events_on_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_security_events_on_reviewed_by_id ON public.security_events USING btree (reviewed_by_id);


--
-- Name: index_security_events_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_security_events_on_status_and_created_at ON public.security_events USING btree (status, created_at);


--
-- Name: index_security_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_security_events_on_user_id ON public.security_events USING btree (user_id);


--
-- Name: index_security_events_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_security_events_on_user_id_and_created_at ON public.security_events USING btree (user_id, created_at);


--
-- Name: index_transfers_on_destination_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_destination_account_id ON public.transfers USING btree (destination_account_id);


--
-- Name: index_transfers_on_ledger_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_transfers_on_ledger_transaction_id ON public.transfers USING btree (ledger_transaction_id);


--
-- Name: index_transfers_on_source_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_source_account_id ON public.transfers USING btree (source_account_id);


--
-- Name: index_users_on_cpf; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_cpf ON public.users USING btree (cpf);


--
-- Name: index_users_on_normalized_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_normalized_email ON public.users USING btree (lower((email)::text));


--
-- Name: ledger_entry_per_account; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ledger_entry_per_account ON public.ledger_entries USING btree (ledger_transaction_id, ledger_account_id);


--
-- Name: ledger_user_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ledger_user_idempotency ON public.ledger_transactions USING btree (user_id, idempotency_key);


--
-- Name: one_active_credit_rule; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_active_credit_rule ON public.credit_rules USING btree (active) WHERE (active = true);


--
-- Name: one_pending_appeal_per_loan; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX one_pending_appeal_per_loan ON public.loan_appeals USING btree (loan_id) WHERE ((status)::text = 'pending_review'::text);


--
-- Name: schedule_user_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX schedule_user_idempotency ON public.scheduled_transfers USING btree (user_id, idempotency_key);


--
-- Name: audit_logs audit_logs_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_logs_immutable BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.reject_audit_log_mutation();


--
-- Name: ledger_entries balanced_ledger_entry; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER balanced_ledger_entry AFTER INSERT ON public.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_ledger_balance();


--
-- Name: ledger_transactions balanced_ledger_transaction; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER balanced_ledger_transaction AFTER INSERT ON public.ledger_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_ledger_balance();


--
-- Name: accounts consistent_account_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER consistent_account_balance AFTER INSERT OR UPDATE ON public.accounts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_account_ledger_balance();


--
-- Name: ledger_entries consistent_entry_account_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER consistent_entry_account_balance AFTER INSERT ON public.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_account_ledger_balance();


--
-- Name: accounts immutable_account_identity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immutable_account_identity BEFORE UPDATE ON public.accounts FOR EACH ROW EXECUTE FUNCTION public.protect_account_identity();


--
-- Name: ledger_accounts immutable_ledger_accounts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immutable_ledger_accounts BEFORE DELETE OR UPDATE ON public.ledger_accounts FOR EACH ROW EXECUTE FUNCTION public.reject_ledger_mutation();


--
-- Name: ledger_entries immutable_ledger_entries; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immutable_ledger_entries BEFORE DELETE OR UPDATE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.reject_ledger_mutation();


--
-- Name: ledger_transactions immutable_ledger_transactions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immutable_ledger_transactions BEFORE DELETE OR UPDATE ON public.ledger_transactions FOR EACH ROW EXECUTE FUNCTION public.reject_ledger_mutation();


--
-- Name: transfers immutable_transfers; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER immutable_transfers BEFORE DELETE OR UPDATE ON public.transfers FOR EACH ROW EXECUTE FUNCTION public.reject_ledger_mutation();


--
-- Name: transfers fk_rails_1df0f39847; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_1df0f39847 FOREIGN KEY (ledger_transaction_id) REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT;


--
-- Name: audit_logs fk_rails_1f26bc34ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_1f26bc34ae FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: security_events fk_rails_2ea9674550; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_events
    ADD CONSTRAINT fk_rails_2ea9674550 FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- Name: auth_sessions fk_rails_4aba5b3f33; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT fk_rails_4aba5b3f33 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: loan_appeals fk_rails_5e12aa1665; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_appeals
    ADD CONSTRAINT fk_rails_5e12aa1665 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: investment_profiles fk_rails_7afabeff62; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investment_profiles
    ADD CONSTRAINT fk_rails_7afabeff62 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: scheduled_transfers fk_rails_7eceab3d49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_transfers
    ADD CONSTRAINT fk_rails_7eceab3d49 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: loan_installments fk_rails_866fd375ad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT fk_rails_866fd375ad FOREIGN KEY (loan_id) REFERENCES public.loans(id) ON DELETE RESTRICT;


--
-- Name: scheduled_transfers fk_rails_884598e789; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_transfers
    ADD CONSTRAINT fk_rails_884598e789 FOREIGN KEY (ledger_transaction_id) REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT;


--
-- Name: ledger_entries fk_rails_942ef43aa4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_942ef43aa4 FOREIGN KEY (ledger_account_id) REFERENCES public.ledger_accounts(id) ON DELETE RESTRICT;


--
-- Name: ledger_transactions fk_rails_969c84a0e1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions
    ADD CONSTRAINT fk_rails_969c84a0e1 FOREIGN KEY (reverses_id) REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT;


--
-- Name: loan_appeals fk_rails_97883874dc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_appeals
    ADD CONSTRAINT fk_rails_97883874dc FOREIGN KEY (loan_id) REFERENCES public.loans(id) ON DELETE RESTRICT;


--
-- Name: ledger_transactions fk_rails_9eb516ca65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_transactions
    ADD CONSTRAINT fk_rails_9eb516ca65 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: transfers fk_rails_a25903a37d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_a25903a37d FOREIGN KEY (source_account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: accounts fk_rails_b1e30bebc8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT fk_rails_b1e30bebc8 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: ledger_accounts fk_rails_bf15238832; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_accounts
    ADD CONSTRAINT fk_rails_bf15238832 FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- Name: loans fk_rails_bf22ff94a9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT fk_rails_bf22ff94a9 FOREIGN KEY (reviewed_by_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: loans fk_rails_c15c911198; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT fk_rails_c15c911198 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: transfers fk_rails_c234e54e9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_c234e54e9c FOREIGN KEY (destination_account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- Name: ledger_entries fk_rails_cb26505157; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_cb26505157 FOREIGN KEY (ledger_transaction_id) REFERENCES public.ledger_transactions(id) ON DELETE RESTRICT;


--
-- Name: financial_goals fk_rails_cdd9c797dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_goals
    ADD CONSTRAINT fk_rails_cdd9c797dd FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: purpose_tokens fk_rails_d6f0ed0c16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.purpose_tokens
    ADD CONSTRAINT fk_rails_d6f0ed0c16 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: security_events fk_rails_da5899dcce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_events
    ADD CONSTRAINT fk_rails_da5899dcce FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: investment_simulations fk_rails_e5650b92a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.investment_simulations
    ADD CONSTRAINT fk_rails_e5650b92a4 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: financial_rules fk_rails_ed65a353fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.financial_rules
    ADD CONSTRAINT fk_rails_ed65a353fb FOREIGN KEY (updated_by_id) REFERENCES public.users(id);


--
-- Name: security_events fk_rails_f549d51c04; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_events
    ADD CONSTRAINT fk_rails_f549d51c04 FOREIGN KEY (reviewed_by_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: scheduled_transfers fk_rails_f80078effb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_transfers
    ADD CONSTRAINT fk_rails_f80078effb FOREIGN KEY (destination_account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- Name: scheduled_transfers fk_rails_fd2688c5ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_transfers
    ADD CONSTRAINT fk_rails_fd2688c5ca FOREIGN KEY (source_account_id) REFERENCES public.accounts(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261020000007'),
('20261020000006'),
('20261020000005'),
('20261020000004'),
('20261020000003'),
('20261020000002'),
('20261020000001');
