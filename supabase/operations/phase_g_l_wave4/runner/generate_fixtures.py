#!/usr/bin/env python3
"""
Generate Phase G-L Wave 4 test fixtures (positive + 3 negative variants)
Usage: generate_fixtures.py <stage_dir> <variant>
  variant: positive | neg1 | neg2 | neg3
"""
import os, sys

stage = sys.argv[1]
variant = sys.argv[2] if len(sys.argv) > 2 else 'positive'
os.makedirs(stage, exist_ok=True)

# Reusable column lists
CUST_COLS = ['id','created_at','updated_at','user_id','email','name','phone','default_pickup_address','archived','archived_at','auth_user_linked','auth_user_linked_at','is_active','no_email','no_session','status','approved','approved_at','auto_approved_at','rejected','rejected_at','pending','approval_not_required','request_scope','username','customer_profile_upserted_at']
PART_COLS = ['legacy_pk','created_at','updated_at','user_id','email','name','phone','is_hoofd','company','notes','account_type','archived_at','default_pickup_address','contact','driver','kind','operations','pending_request','primary_dispatch_driver_id']
DRV_COLS = ['id','created_at','updated_at','partner_legacy_pk','user_id','email','name','phone','vehicle','license_plate','color','driver_code','preferred_language','is_active','archived_at']
BK_COLS = ['id','created_at','pickup','destination','status','customer_id','partner_legacy_pk','driver_legacy_uuid','user_id','email','name','phone','notes','payment_status','assigned_driver','route_distance_km','route_duration_min','extras','flight_number','vehicle','license_plate','assignment_token','pickup_place_id','dropoff_place_id','assignment_sent_at','assignment_accepted_at','assignment_declined_at','pwa_driver_can_act','form_data','metadata','amount','payment','time','datetime']

# --- POSITIVE: 3 customers, 2 partners, 2 drivers, 4 bookings ---
POS_CUSTOMERS = [
    ['CUST-LEG-001','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','11111111-1111-1111-1111-111111111111','alice@legacy.example','Alice Legacy','P-A-001','Brussels 1','false','','false','','true','false','false','approved','true','2026-01-01T00:00:00Z','','false','','false','false','','alice_legacy',''],
    ['CUST-LEG-002','2026-01-02T00:00:00Z','2026-01-02T00:00:00Z','22222222-2222-2222-2222-222222222222','bob@legacy.example','Bob Legacy','P-A-002','Brussels 2','false','','false','','true','false','false','approved','true','2026-01-02T00:00:00Z','','false','','false','false','','bob_legacy',''],
    ['CUST-LEG-003','2026-01-03T00:00:00Z','2026-01-03T00:00:00Z','33333333-3333-3333-3333-333333333333','carol@legacy.example','Carol Legacy','P-B-001','Brussels 3','false','','false','','true','false','false','approved','true','2026-01-03T00:00:00Z','','false','','false','false','','carol_legacy',''],
]
POS_PARTNERS = [
    [101,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','44444444-4444-4444-4444-444444444444','partner-a@legacy.example','Partner A','P-B-002','true','Partner A Co','','partner','','','','','','','',''],
    [102,'2026-01-02T00:00:00Z','2026-01-02T00:00:00Z','55555555-5555-5555-5555-555555555555','partner-b@legacy.example','Partner B','P-C-001','false','Partner B Co','','partner','','','','','','','',''],
]
POS_DRIVERS = [
    ['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z',101,'66666666-6666-6666-6666-666666666666','driver-a@legacy.example','Driver A','P-C-002','Toyota Camry','ABC-123','Black','DA001','nl','true',''],
    ['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','2026-01-02T00:00:00Z','2026-01-02T00:00:00Z',102,'77777777-7777-7777-7777-777777777777','driver-b@legacy.example','Driver B','P-D-001','Honda Civic','XYZ-789','White','DB002','nl','true',''],
]
POS_BOOKINGS = [
    ['BK-LEG-0001','2026-02-01T10:00:00Z','Brussels Airport','Vilvoorde Center','completed','CUST-LEG-001',101,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','alice@legacy.example','Alice','P-A-001','','paid','','25.0','30','','','Toyota Camry','ABC-123','','','','','','','false','','','30.00','','2026-02-01T10:00:00Z','2026-02-01T10:00:00Z'],
    ['BK-LEG-0002','2026-02-02T11:00:00Z','Brussels Airport','Vilvoorde Center','completed','CUST-LEG-002',101,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','22222222-2222-2222-2222-222222222222','bob@legacy.example','Bob','P-A-002','','paid','','15.0','20','','','Toyota Camry','ABC-123','','','','','','','false','','','15.00','','2026-02-02T11:00:00Z','2026-02-02T11:00:00Z'],
    ['BK-LEG-0003','2026-02-03T12:00:00Z','Campanile','Brussels Airport','in_progress','CUST-LEG-003',102,'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','33333333-3333-3333-3333-333333333333','carol@legacy.example','Carol','P-B-001','','pending','','25.0','30','','','Honda Civic','XYZ-789','','','','','','','false','','','25.00','','2026-02-03T12:00:00Z','2026-02-03T12:00:00Z'],
    ['BK-LEG-0004','2026-02-04T13:00:00Z','The Lodge','Brussels Airport','pending','CUST-LEG-001',102,'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','11111111-1111-1111-1111-111111111111','alice@legacy.example','Alice','P-A-001','','pending','','12.0','18','','','Honda Civic','XYZ-789','','','','','','','false','','','12.00','','2026-02-04T13:00:00Z','2026-02-04T13:00:00Z'],
]
POS_MAPPING = [
    ['legacy_user_id','new_user_id','re_onboard_status'],
    ['11111111-1111-1111-1111-111111111111','cccccccc-cccc-cccc-cccc-cccccccccccc','CREATED'],
    ['22222222-2222-2222-2222-222222222222','dddddddd-dddd-dddd-dddd-dddddddddddd','CREATED'],
    ['33333333-3333-3333-3333-333333333333','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','CREATED'],
    ['44444444-4444-4444-4444-444444444444','ffffffff-ffff-ffff-ffff-ffffffffffff','CREATED'],
    ['55555555-5555-5555-5555-555555555555','99999999-9999-9999-9999-999999999999','CREATED'],
    ['66666666-6666-6666-6666-666666666666','88888888-8888-8888-8888-888888888888','CREATED'],
    ['77777777-7777-7777-7777-777777777777','7a7a7a7a-7a7a-7a7a-7a7a-7a7a7a7a7a7a','CREATED'],
]

def write_csv(name, header, rows):
    with open(f'{stage}/{name}','w') as f:
        f.write(','.join(header) + '\n')
        for row in rows:
            f.write(','.join('' if v is None else str(v) for v in row) + '\n')

def write_mapping(rows):
    with open(f'{stage}/mapping.csv','w') as f:
        for r in rows:
            f.write(','.join(r) + '\n')

if variant == 'positive':
    write_csv('customers.csv', CUST_COLS, POS_CUSTOMERS)
    write_csv('partners.csv', PART_COLS, POS_PARTNERS)
    write_csv('drivers.csv', DRV_COLS, POS_DRIVERS)
    write_csv('bookings.csv', BK_COLS, POS_BOOKINGS)
    write_mapping(POS_MAPPING)
elif variant == 'neg1':
    # Duplicate partner email -> ABORT at A.2 preflight
    cust_1 = [POS_CUSTOMERS[0]]  # only one customer needed
    write_csv('customers.csv', CUST_COLS, cust_1)
    # Two partners, both have email "partner-a@legacy.example" -> A.2 fails
    dup_partners = [
        [101,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','44444444-4444-4444-4444-444444444444','partner-a@legacy.example','Partner A','P-B-002','true','Partner A Co','','partner','','','','','','','',''],
        [102,'2026-01-02T00:00:00Z','2026-01-02T00:00:00Z','55555555-5555-5555-5555-555555555555','partner-a@legacy.example','Partner A duplicate','P-C-001','false','Partner A Co','','partner','','','','','','','',''],
    ]
    write_csv('partners.csv', PART_COLS, dup_partners)
    drv_1 = [POS_DRIVERS[0]]
    write_csv('drivers.csv', DRV_COLS, drv_1)
    bk_1 = [POS_BOOKINGS[0]]
    write_csv('bookings.csv', BK_COLS, bk_1)
    write_mapping(POS_MAPPING)
elif variant == 'neg2':
    # Orphan driver.partner_legacy_pk=999 -> ABORT at A.3 preflight
    cust_1 = [POS_CUSTOMERS[0]]
    write_csv('customers.csv', CUST_COLS, cust_1)
    parts_1 = [POS_PARTNERS[0]]  # only legacy_pk=101 exists
    write_csv('partners.csv', PART_COLS, parts_1)
    drv_orphan = [
        ['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','2026-01-01T00:00:00Z','2026-01-01T00:00:00Z',999,'66666666-6666-6666-6666-666666666666','driver-a@legacy.example','Driver A','P-C-002','Toyota Camry','ABC-123','Black','DA001','nl','true',''],
    ]
    write_csv('drivers.csv', DRV_COLS, drv_orphan)
    bk_1 = [POS_BOOKINGS[0]]
    write_csv('bookings.csv', BK_COLS, bk_1)
    write_mapping(POS_MAPPING)
elif variant == 'neg3':
    # Mapping row references nonexistent new_user_id -> ABORT at B.2 preflight
    write_csv('customers.csv', CUST_COLS, POS_CUSTOMERS)
    write_csv('partners.csv', PART_COLS, POS_PARTNERS)
    write_csv('drivers.csv', DRV_COLS, POS_DRIVERS)
    write_csv('bookings.csv', BK_COLS, POS_BOOKINGS)
    # carol's new_user_id (eee...) is NOT pre-created in auth.users
    bad_mapping = [
        ['legacy_user_id','new_user_id','re_onboard_status'],
        ['11111111-1111-1111-1111-111111111111','cccccccc-cccc-cccc-cccc-cccccccccccc','CREATED'],
        ['22222222-2222-2222-2222-222222222222','dddddddd-dddd-dddd-dddd-dddddddddddd','CREATED'],
        ['33333333-3333-3333-3333-333333333333','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','CREATED'],  # bogus target
        ['44444444-4444-4444-4444-444444444444','ffffffff-ffff-ffff-ffff-ffffffffffff','CREATED'],
        ['55555555-5555-5555-5555-555555555555','99999999-9999-9999-9999-999999999999','CREATED'],
        ['66666666-6666-6666-6666-666666666666','88888888-8888-8888-8888-888888888888','CREATED'],
        ['77777777-7777-7777-7777-777777777777','7a7a7a7a-7a7a-7a7a-7a7a-7a7a7a7a7a7a','CREATED'],
    ]
    write_mapping(bad_mapping)
else:
    print(f'Unknown variant: {variant}', file=sys.stderr)
    sys.exit(1)

print(f'Generated {variant} fixtures in {stage}')
