# FleetConnect B2B WebBooker MVP Report

## Status

WEBBOOKER MVP READY FOR HOTEL / B2B DEMOS

## Implemented

- Added a mobile-first B2B WebBooker at `/b2b/webbooker`.
- Added `/b2b` as a simple entry route into the WebBooker.
- Reused the existing `create_public_booking` RPC and existing booking lifecycle.
- Stored B2B attribution in `form_data` and `metadata` instead of creating a separate booking system.
- Added operator dashboard visibility for B2B bookings in New Orders, Orders, History, and the booking fiche.
- Added EN, FR, NL, ES, and AR copy with English-first language resolution and Arabic RTL behavior.

## Routes

- `/b2b`
- `/b2b/webbooker`

## Booking Lifecycle Result

WebBooker submissions create normal `bookings` records with `status = pending`, so they enter the existing FleetConnect lifecycle:

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

## Known MVP Limitations

- Company profiles and company-level booking volume/history reporting are not built yet.
- Price confirmation is operator-led for B2B MVP intake.
- Full B2B account login, invoicing, vouchers, PEPPOL, refunds, and financial continuity remain future Phase C scope.

## Validation

- `vercel.json` parses successfully.
- WebBooker static route/RPC/attribution markers are present.
- WebBooker inline module script parses successfully.
- Operator dashboard inline script parses successfully.
- Secret scan of changed B2B/dashboard/routing surfaces found no service-role or Stripe secrets.
