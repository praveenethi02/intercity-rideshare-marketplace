-- Store first and last names separately. full_name stays as "first last" so that search,
-- the admin pages and other modules keep working without changes.

ALTER TABLE users
  ADD COLUMN first_name VARCHAR(50) NOT NULL DEFAULT '',
  ADD COLUMN last_name VARCHAR(50) NOT NULL DEFAULT '';

-- Existing users: the first word is the first name and the rest is the last name.
-- A one-word name keeps an empty last name until the user edits their profile.
UPDATE users
SET first_name = left(split_part(btrim(full_name), ' ', 1), 50),
    last_name = left(btrim(substr(btrim(full_name), length(split_part(btrim(full_name), ' ', 1)) + 1)), 50);
