-- Driver Management and Verification (SCRUM-38 to SCRUM-47).
-- Vehicle and trip modules read driver_profiles.verification_status and account_status.

CREATE TABLE driver_profiles (
  user_id UUID PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  license_number TEXT NOT NULL UNIQUE,
  license_expiry DATE NOT NULL,
  nic_number TEXT NOT NULL UNIQUE,
  date_of_birth DATE,
  address TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  bank_account JSONB,
  verification_status TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (verification_status IN ('PENDING', 'APPROVED', 'REJECTED')),
  rejection_reason TEXT,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users (id),
  account_status TEXT NOT NULL DEFAULT 'ACTIVE'
    CHECK (account_status IN ('ACTIVE', 'SUSPENDED', 'DEACTIVATED')),
  rating_avg NUMERIC(3, 2) NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX driver_profiles_verification_status_idx ON driver_profiles (verification_status);
CREATE INDEX driver_profiles_account_status_idx ON driver_profiles (account_status);

-- One current file per document type. Uploading the same type again replaces it.
CREATE TABLE driver_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id UUID NOT NULL REFERENCES driver_profiles (user_id) ON DELETE CASCADE,
  doc_type TEXT NOT NULL
    CHECK (doc_type IN ('LICENCE_FRONT', 'LICENCE_BACK', 'NIC_FRONT', 'NIC_BACK', 'PROFILE_PHOTO')),
  storage_key TEXT NOT NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (driver_user_id, doc_type)
);

-- The admin review queue, shared with vehicles, so subject_id has no foreign key:
-- it is a driver's user id when type = 'DRIVER' and a vehicle id when type = 'VEHICLE'.
CREATE TABLE verification_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('DRIVER', 'VEHICLE')),
  subject_id UUID NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  reason TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ,
  decided_by UUID REFERENCES users (id)
);

-- A subject can have only one open request at a time.
CREATE UNIQUE INDEX verification_requests_one_pending_idx
  ON verification_requests (type, subject_id) WHERE status = 'PENDING';
CREATE INDEX verification_requests_queue_idx ON verification_requests (status, submitted_at);
CREATE INDEX verification_requests_subject_idx
  ON verification_requests (type, subject_id, submitted_at DESC);

-- Other modules can write here too, so it may be created by whichever migration lands first.
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID NOT NULL REFERENCES users (id),
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
