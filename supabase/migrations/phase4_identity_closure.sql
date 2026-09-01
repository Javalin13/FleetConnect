-- PHASE 4: Identity Closure & Ownership Enforcement

-- 1. Ensure customers table uses UUID and links to auth.users
-- We add user_id column to map existing customers to auth.users if needed
ALTER TABLE customers ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS idx_customers_user_id ON customers(user_id);

-- 2. Update bookings for strict ownership
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id);
CREATE INDEX IF NOT EXISTS idx_bookings_user_id ON bookings(user_id);

-- 3. RLS Policies for Customers
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view own profile" ON customers;
CREATE POLICY "Customers can view own profile"
ON customers FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR email = auth.jwt()->>'email');

DROP POLICY IF EXISTS "Customers can update own profile" ON customers;
CREATE POLICY "Customers can update own profile"
ON customers FOR UPDATE
TO authenticated
USING (user_id = auth.uid());

-- 4. RLS Policies for Bookings (Ownership Model)
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

-- Customers see only own bookings
DROP POLICY IF EXISTS "Customers can view own bookings" ON bookings;
CREATE POLICY "Customers can view own bookings"
ON bookings FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR email = auth.jwt()->>'email');

-- Customers can only mutate own bookings (limited to pending/unpaid or specific states if business rules allow)
DROP POLICY IF EXISTS "Customers can update own bookings" ON bookings;
CREATE POLICY "Customers can update own bookings"
ON bookings FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Ownership auto-bound to auth uid on insert
DROP POLICY IF EXISTS "Customers can insert own bookings" ON bookings;
CREATE POLICY "Customers can insert own bookings"
ON bookings FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- 5. Helper for triggers: Auto-assign user_id based on email if available
CREATE OR REPLACE FUNCTION public.sync_booking_user_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.user_id IS NULL AND auth.uid() IS NOT NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_sync_booking_user_id ON bookings;
CREATE TRIGGER tr_sync_booking_user_id
BEFORE INSERT ON bookings
FOR EACH ROW EXECUTE FUNCTION sync_booking_user_id();

-- 6. Grant access to service_role for system operations
-- PRIME r056 Phase G-H (per Lux d3a5d92 §4 authorized minimal additive fix):
-- add DROP POLICY IF EXISTS so this migration is idempotent on re-apply
-- to a populated DB. Semantic policy unchanged: full access for service_role.
DROP POLICY IF EXISTS "Service role full access on bookings" ON bookings;
CREATE POLICY "Service role full access on bookings" ON bookings FOR ALL TO service_role USING (true);
DROP POLICY IF EXISTS "Service role full access on customers" ON customers;
CREATE POLICY "Service role full access on customers" ON customers FOR ALL TO service_role USING (true);
