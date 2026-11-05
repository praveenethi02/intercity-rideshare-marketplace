-- Vehicles and their verification documents (SCRUM-48).
-- A trip can only use a vehicle that is APPROVED and active: see isVehicleUsable in vehicle.service.js.

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  vehicle_type TEXT NOT NULL
    CHECK (vehicle_type IN ('CAR', 'VAN', 'SUV', 'MINIBUS', 'BUS', 'PICKUP', 'LORRY')),
  make TEXT NOT NULL,
  model TEXT NOT NULL,
  year INTEGER NOT NULL CHECK (year >= 1990),
  color TEXT NOT NULL,
  plate_number TEXT NOT NULL UNIQUE,
  total_seats INTEGER NOT NULL,
  passenger_seats INTEGER NOT NULL,
  cargo_capacity_kg INTEGER NOT NULL DEFAULT 0,
  cargo_volume_l INTEGER NOT NULL DEFAULT 0,
  verification_status TEXT NOT NULL DEFAULT 'NOT_SUBMITTED'
    CHECK (verification_status IN ('NOT_SUBMITTED', 'PENDING', 'APPROVED', 'REJECTED')),
  rejection_reason TEXT,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users (id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT vehicles_seats_chk CHECK (passenger_seats >= 1 AND passenger_seats < total_seats),
  CONSTRAINT vehicles_cargo_chk CHECK (cargo_capacity_kg >= 0 AND cargo_volume_l >= 0)
);

CREATE INDEX vehicles_driver_user_id_idx ON vehicles (driver_user_id);
CREATE INDEX vehicles_verification_status_idx ON vehicles (verification_status);

-- One current file per document type. Uploading the same type again replaces it.
CREATE TABLE vehicle_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id UUID NOT NULL REFERENCES vehicles (id) ON DELETE CASCADE,
  doc_type TEXT NOT NULL
    CHECK (doc_type IN ('REGISTRATION_CERT', 'REVENUE_LICENSE', 'INSURANCE',
                        'PHOTO_FRONT', 'PHOTO_BACK', 'PHOTO_INTERIOR')),
  storage_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'UPLOADED'
    CHECK (status IN ('UPLOADED', 'ACCEPTED', 'REJECTED')),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT vehicle_documents_vehicle_doc_type_uq UNIQUE (vehicle_id, doc_type)
);
