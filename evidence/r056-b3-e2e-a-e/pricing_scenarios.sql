-- r056 Phase A — Campanile + The Lodge pricing scenarios
-- Per Lux r053 §5: pricing guards remain canonical
-- Campanile ↔ Airport €25 / €30 fixed

SELECT 'Campanile → Brussels Airport' AS scenario,
       public.calculate_booking_fare(15, 'Luchthavenlaan 2, 1800 Vilvoorde', 'Brussels Airport', false, 1) AS result
UNION ALL
SELECT 'Brussels Airport → Campanile',
       public.calculate_booking_fare(15, 'Brussels Airport', 'Luchthavenlaan 2, 1800 Vilvoorde', false, 1)
UNION ALL
SELECT 'Campanile (no-comma) → Brussels Airport',
       public.calculate_booking_fare(15, 'Luchthavenlaan 2 1800 Vilvoorde', 'Brussels Airport', false, 1)
UNION ALL
SELECT 'The Lodge local Vilvoorde → Vilvoorde Centrum',
       public.calculate_booking_fare(3, 'The Lodge Vilvoorde', 'Vilvoorde Centrum', false, 1)
UNION ALL
SELECT 'Luchthavenlaan 18 → Vilvoorde Centrum (€15 guard)',
       public.calculate_booking_fare(3, 'luchthavenlaan 18, 1800 vilvoorde', 'vilvoorde centrum', false, 1)
UNION ALL
SELECT 'Brussels Airport → Mechelen (airport rule)',
       public.calculate_booking_fare(25, 'Brussels Airport', 'Mechelen Centrum', false, 1);