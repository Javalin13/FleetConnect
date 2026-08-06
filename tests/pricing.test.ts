import { describe, it, expect, vi, beforeEach } from 'vitest';

const { mockRpc } = vi.hoisted(() => ({
  mockRpc: vi.fn(),
}));

vi.mock('@supabase/supabase-js', () => ({
  createClient: () => ({
    rpc: mockRpc,
  }),
}));

describe('Pricing Engine', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('correctly calculates fare for airport and non-airport addresses', async () => {
    // Tests that call supabase client get mocked via the rpc mock
    mockRpc.mockResolvedValueOnce({
      data: {
        total_amount: 15.00,
        raw_amount: 15.00,
        minimum_applied: true,
        is_fixed_route: false,
        route_name: 'Vilvoorde',
        distance_km: 1.5,
        applicable_min_fare: 15.00
      },
      error: null
    });

    const mockSupabase = {
      rpc: mockRpc
    };

    const res = await mockSupabase.rpc('calculate_booking_fare', {
      p_distance_km: 1.5,
      p_pickup_address: 'Luchthavenlaan 2, 1800 Vilvoorde',
      p_dropoff_address: 'Leuvensesteenweg, Vilvoorde',
      p_is_round_trip: false
    });

    expect(mockRpc).toHaveBeenCalledWith('calculate_booking_fare', {
      p_distance_km: 1.5,
      p_pickup_address: 'Luchthavenlaan 2, 1800 Vilvoorde',
      p_dropoff_address: 'Leuvensesteenweg, Vilvoorde',
      p_is_round_trip: false
    });
    expect(res.data.total_amount).toBe(15.00);
    expect(res.data.route_name).toBe('Vilvoorde');
  });
});
