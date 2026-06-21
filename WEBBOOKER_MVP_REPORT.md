# FleetConnect B2B WebBooker MVP Report

## Status

WEBBOOKER MVP READY FOR HOTEL / B2B DEMOS

## Implemented

- Added a mobile-first B2B WebBooker at `/b2b/webbooker`.
- Added `/b2b` as a simple entry route into the WebBooker.
- Added `/b2b/login` and `/b2b/portal` as the B2B account entry shell for approved hotels, companies, congress centers and event partners.
- Reused the existing `create_public_booking` RPC and existing booking lifecycle.
- Stored B2B attribution in `form_data` and `metadata` instead of creating a separate booking system.
- Added operator dashboard visibility for B2B bookings in New Orders, Orders, History, and the booking fiche.
- Added EN, FR, NL, ES, and AR copy with English-first language resolution, dropdown language selection, persistence, and Arabic RTL behavior.
- Aligned WebBooker routing/pricing with the certified public booking form by using Google address suggestions, map display, distance, duration and minimum EUR 15 pricing before submit.

## Routes

- `/b2b`
- `/b2b/webbooker`
- `/b2b/login`
- `/b2b/portal`

## Booking Lifecycle Result

WebBooker submissions create normal `bookings` records with `status = pending`, positive calculated amount, route distance and route duration, so they enter the existing FleetConnect lifecycle:

Booking Created -> Operator Review -> Booking Accepted -> Driver Assignment -> Driver Accept/Decline -> Completion.

## Attribution Captured

- `booking_source = b2b`
- `source_route = /b2b/webbooker`
- `business_type`
- `company_name`
- `company_contact_name`
- `company_contact_email`
- `company_contact_phone`
- `passenger_name`
- `passenger_phone`
- `passenger_email`
- `flight_number`
- `notes`
- `payment_method`

## Security / RLS

- No service-role key is exposed.
- No dashboard data is exposed publicly.
- No RLS policy was weakened.
- No new public read surface was added.
- Public submission uses the existing `create_public_booking` RPC.
- The B2B portal shell requires an existing Supabase Auth session and does not expose private dashboard data.

## Known MVP Limitations

- Company profiles and company-level booking volume/history reporting are not built yet.
- Price is calculated before submit using the same EUR 1.50/km and minimum EUR 15 public booking model.
- B2B account approval/profile management remains aligned with existing Supabase Auth/account-request infrastructure and can be expanded in Phase C.
- Full B2B account login, invoicing, vouchers, PEPPOL, refunds, and financial continuity remain future Phase C scope.

## Validation

- `vercel.json` parses successfully.
- WebBooker static route/RPC/attribution markers are present.
- WebBooker inline module script parses successfully.
- Operator dashboard inline script parses successfully.
- Secret scan of changed B2B/dashboard/routing surfaces found no service-role or Stripe secrets.
- B2B WebBooker uses the valid FleetConnect Supabase anon key and the existing Google Maps key used by certified public booking pages.
