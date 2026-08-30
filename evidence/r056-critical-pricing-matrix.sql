-- r056 Phase 1 — Lux §3 Required pricing matrix (8 scenarios)
-- After €1.80/km migration. Exact addresses + distance + RPC + result per scenario.

-- 1. local Vilvoorde short ride → €15 minimum
SELECT '1. local Vilvoorde short ride' AS scenario,
       'Luchthavenlaan 18, 1800 Vilvoorde → Vilvoorde Centrum' AS addresses,
       3 AS distance_km,
       public.calculate_booking_fare(3, 'luchthavenlaan 18, 1800 vilvoorde', 'vilvoorde centrum', false, 1) AS result;

-- 2. The Lodge/local Vilvoorde → correct local price
SELECT '2. The Lodge → Vilvoorde Centrum' AS scenario,
       'The Lodge Vilvoorde → Vilvoorde Centrum' AS addresses,
       3 AS distance_km,
       public.calculate_booking_fare(3, 'the lodge vilvoorde', 'vilvoorde centrum', false, 1) AS result;

-- 3. Luchthavenlaan 18 → local Vilvoorde → €15, non-airport
SELECT '3. Luchthavenlaan 18 → Vilvoorde Centrum (non-airport guard)' AS scenario,
       'Luchthavenlaan 18, 1800 Vilvoorde → Vilvoorde Centrum' AS addresses,
       3 AS distance_km,
       public.calculate_booking_fare(3, 'luchthavenlaan 18, 1800 vilvoorde', 'vilvoorde centrum', false, 1) AS result;

-- 4. ordinary non-airport long-distance ride → €1.80/km-based result
SELECT '4. ordinary non-airport long-distance (50km)' AS scenario,
       'Mechelen → Leuven' AS addresses,
       50 AS distance_km,
       public.calculate_booking_fare(50, 'mechelen', 'leuven', false, 1) AS result;

-- 5. Campanile → Airport → €25 fixed
SELECT '5. Campanile → Brussels Airport' AS scenario,
       'Luchthavenlaan 2, 1800 Vilvoorde (Campanile) → Brussels Airport' AS addresses,
       15 AS distance_km,
       public.calculate_booking_fare(15, 'luchthavenlaan 2, 1800 vilvoorde', 'brussels airport', false, 1) AS result;

-- 6. Airport → Campanile → €30 fixed
SELECT '6. Brussels Airport → Campanile' AS scenario,
       'Brussels Airport → Luchthavenlaan 2, 1800 Vilvoorde (Campanile)' AS addresses,
       15 AS distance_km,
       public.calculate_booking_fare(15, 'brussels airport', 'luchthavenlaan 2, 1800 vilvoorde', false, 1) AS result;

-- 7. genuine airport ordinary route → airport rule/minimum preserved
SELECT '7. Brussels Airport → Mechelen (airport route)' AS scenario,
       'Brussels Airport → Mechelen Centrum' AS addresses,
       25 AS distance_km,
       public.calculate_booking_fare(25, 'brussels airport', 'mechelen', false, 1) AS result;

-- 8. representative Brussels route/minimum preserved
SELECT '8. Brussels city route' AS scenario,
       'Brussels Centrum → Brussels Etterbeek' AS addresses,
       5 AS distance_km,
       public.calculate_booking_fare(5, 'brussels centrum', 'etterbeek brussels', false, 1) AS result;