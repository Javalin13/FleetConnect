import { describe, it, expect } from 'vitest';

const HOTEL_ADRES = 'luchthavenlaan 2';
const HOTEL_KORTING = 5.00;
const HOTEL_NAAM = 'Campanile Vilvoorde';
const FLEETCONNECT_PRICING = {
    minimumTarief: 30.00,
    prijsPerKm: 1.50,
    regioRadius: 15,
    luchthavenPrijs: 35.00
};

function normalizeAddress(addr: string): string {
    return addr.toLowerCase().trim();
}

function berekenFleetconnectPrijs(afstandKm: number, pickupAdres: string, dropoffAdres: string, isRoundTrip: boolean) {
    const { prijsPerKm, regioRadius, luchthavenPrijs } = FLEETCONNECT_PRICING;

    const pickupNormalized = normalizeAddress(pickupAdres || '').toLowerCase();
    const dropoffNormalized = normalizeAddress(dropoffAdres || '').toLowerCase();

    const isHotelPickup = pickupNormalized.includes(HOTEL_ADRES);
    const isHotelDropoff = dropoffNormalized.includes(HOTEL_ADRES);

    const isLuchthavenAddress = (addr: string) => {
        if (!addr) return false;
        const lower = addr.toLowerCase();
        const cleaned = lower.replace(/luchthavenlaan/g, '').replace(/luchthavenweg/g, '');
        return cleaned.includes('zaventem') || cleaned.includes('brussels airport') || cleaned.includes('luchthaven');
    };

    const isLuchthavenPickup = isLuchthavenAddress(pickupAdres);
    const isLuchthavenDropoff = isLuchthavenAddress(dropoffAdres);

    // Dynamic region-aware minimum fare calculation
    let applicableMinFare = 30.00; // Default Brussels / other regions minimum
    let regionName = 'Standaard';

    const hasVilvoordeInvolved = (pickupAdres && (pickupAdres.toLowerCase().includes('vilvoorde') || pickupAdres.toLowerCase().includes('machelen') || pickupAdres.toLowerCase().includes('peutie') || pickupAdres.toLowerCase().includes('perk') || pickupAdres.toLowerCase().includes('grimbergen') || pickupAdres.toLowerCase().includes('zemst'))) ||
                                 (dropoffAdres && (dropoffAdres.toLowerCase().includes('vilvoorde') || dropoffAdres.toLowerCase().includes('machelen') || dropoffAdres.toLowerCase().includes('peutie') || dropoffAdres.toLowerCase().includes('perk') || dropoffAdres.toLowerCase().includes('grimbergen') || dropoffAdres.toLowerCase().includes('zemst')));

    const hasBrusselsInvolved = (pickupAdres && (pickupAdres.toLowerCase().includes('brussel') || pickupAdres.toLowerCase().includes('bruxelles') || pickupAdres.toLowerCase().includes('brussels'))) ||
                                (dropoffAdres && (dropoffAdres.toLowerCase().includes('brussel') || dropoffAdres.toLowerCase().includes('bruxelles') || dropoffAdres.toLowerCase().includes('brussels')));

    if (isLuchthavenPickup || isLuchthavenDropoff) {
        applicableMinFare = 30.00;
        regionName = 'Luchthaven';
    } else if (hasBrusselsInvolved) {
        applicableMinFare = 30.00;
        regionName = 'Brussel';
    } else if (hasVilvoordeInvolved) {
        applicableMinFare = 15.00;
        regionName = 'Vilvoorde';
    }

    let basisPrijsPerRit = 0;
    let ritOmschrijving = '';
    let korting = 0;
    let isHotelKorting = false;
    let hotelWeergave = '';

    if (isHotelPickup && isLuchthavenDropoff) {
        basisPrijsPerRit = 30.00; // Fixed Campanile -> Zaventem base before discount
        ritOmschrijving = 'Hotel → Luchthaven';
        korting = HOTEL_KORTING;
        isHotelKorting = true;
        hotelWeergave = `🏨 ${HOTEL_NAAM} - incl. €${korting.toFixed(2)} korting`;
    }
    else if (isLuchthavenPickup && isHotelDropoff) {
        basisPrijsPerRit = luchthavenPrijs; // €35.00
        ritOmschrijving = 'Luchthaven → Hotel';
        korting = HOTEL_KORTING;
        isHotelKorting = true;
        hotelWeergave = `🏨 ${HOTEL_NAAM} - incl. €${korting.toFixed(2)} korting`;
    }
    else if (afstandKm <= regioRadius) {
        basisPrijsPerRit = applicableMinFare;
        ritOmschrijving = `Regio ${regionName}`;
    } else {
        basisPrijsPerRit = Math.max(afstandKm * prijsPerKm, applicableMinFare);
        ritOmschrijving = 'Lange afstand';
    }

    let basisPrijsTotaal;
    let ritType;

    if (isRoundTrip) {
        basisPrijsTotaal = basisPrijsPerRit * 2;
        ritType = ritOmschrijving + ' (heen & terug)';
        if (isHotelKorting) {
            korting = HOTEL_KORTING * 2;
            hotelWeergave = `🏨 ${HOTEL_NAAM} - incl. €${korting.toFixed(2)} korting voor 2 ritten`;
        }
    } else {
        basisPrijsTotaal = basisPrijsPerRit;
        ritType = ritOmschrijving;
    }

    let totaal = Math.max(basisPrijsTotaal - korting, 0);
    let isMinimum = totaal === applicableMinFare && !isRoundTrip && !isHotelKorting;
    let berekening = `€${basisPrijsTotaal.toFixed(2)}`;

    return {
        totaal: totaal,
        basisPrijs: basisPrijsTotaal,
        basisPrijsPerRit: basisPrijsPerRit,
        isMinimum: isMinimum,
        isHotelKorting: isHotelKorting,
        isHotelRit: isHotelKorting,
        ritType: ritType,
        berekening: berekening,
        korting: korting,
        hotelWeergave: hotelWeergave,
        isRoundTrip: isRoundTrip,
        ritOmschrijving: ritOmschrijving,
        isHotelPickup: isHotelPickup,
        isHotelDropoff: isHotelDropoff,
        isLuchthavenPickup: isLuchthavenPickup,
        isLuchthavenDropoff: isLuchthavenDropoff,
        applicableMinFare: applicableMinFare
    };
}

describe('Pricing Engine Regression Protection Tests', () => {

  it('The Lodge, Vilvoorde -> Vilvoorde Station (Vilvoorde regional rate, 2.1km)', () => {
    // Note: The Lodge, Vilvoorde maps to "Luchthavenlaan 2, 1800 Vilvoorde"
    const res = berekenFleetconnectPrijs(2.1, "Luchthavenlaan 2, 1800 Vilvoorde", "Vilvoorde Station", false);
    expect(res.totaal).toBe(15.00);
    expect(res.ritOmschrijving).toBe('Regio Vilvoorde');
    expect(res.applicableMinFare).toBe(15.00);
  });

  it('The Lodge, Vilvoorde -> Brussels Airport (Hotel -> Airport contractual rate with discount, 10.5km)', () => {
    // Note: Hotel is on Luchthavenlaan 2, destination is Zaventem airport
    const res = berekenFleetconnectPrijs(10.5, "Luchthavenlaan 2, 1800 Vilvoorde", "Brussels Airport", false);
    expect(res.totaal).toBe(25.00); // 30.00 base - 5.00 hotel discount
    expect(res.ritOmschrijving).toBe('Hotel → Luchthaven');
  });

  it('A normal Brussels city trip (Brussels regional rate, 5.0km)', () => {
    const res = berekenFleetconnectPrijs(5.0, "Brussels Grand Place", "Brussels Central Station", false);
    expect(res.totaal).toBe(30.00);
    expect(res.ritOmschrijving).toBe('Regio Brussel');
    expect(res.applicableMinFare).toBe(30.00);
  });

  it('A trip outside both Vilvoorde and Airport regions (Standard regional rate, 8.0km)', () => {
    const res = berekenFleetconnectPrijs(8.0, "Gent-Sint-Pieters", "Gent Center", false);
    expect(res.totaal).toBe(30.00);
    expect(res.ritOmschrijving).toBe('Regio Standaard');
    expect(res.applicableMinFare).toBe(30.00);
  });

  it('The identified edge case that caused this bug (Luchthavenlaan string detection)', () => {
    const res = berekenFleetconnectPrijs(1.5, "Luchthavenlaan, Vilvoorde", "Vilvoorde Station", false);
    expect(res.totaal).toBe(15.00);
    expect(res.ritOmschrijving).toBe('Regio Vilvoorde');
    expect(res.applicableMinFare).toBe(15.00);
  });

  it('Additional edge case: Luchthavenweg in Eindhoven (does not trigger Zaventem/Brussels Airport)', () => {
    const res = berekenFleetconnectPrijs(3.0, "Luchthavenweg 10, Eindhoven", "Eindhoven Station", false);
    expect(res.totaal).toBe(30.00);
    expect(res.ritOmschrijving).toBe('Regio Standaard');
    expect(res.applicableMinFare).toBe(30.00);
  });

});
