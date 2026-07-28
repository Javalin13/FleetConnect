import { describe, it, expect, vi, beforeEach } from 'vitest';

// Use vi.hoisted to declare mock functions so they are initialized during hoisting, before imports run!
const { mockSignUp, mockSignInWithPassword, mockSignOut, mockGetSession, mockGetUser, mockRpc } = vi.hoisted(() => ({
  mockSignUp: vi.fn(),
  mockSignInWithPassword: vi.fn(),
  mockSignOut: vi.fn(),
  mockGetSession: vi.fn(),
  mockGetUser: vi.fn(),
  mockRpc: vi.fn(),
}));

vi.mock('@supabase/supabase-js', () => ({
  createClient: () => ({
    auth: {
      signUp: mockSignUp,
      signInWithPassword: mockSignInWithPassword,
      signOut: mockSignOut,
      getSession: mockGetSession,
      getUser: mockGetUser,
    },
    rpc: mockRpc,
  }),
}));

// Now import customerAuth safely
import { customerAuth } from '../src/lib/auth/customerAuth';

describe('Auth Service', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should call signUpCustomer correctly', async () => {
    mockSignUp.mockResolvedValueOnce({ data: { user: { id: '123' } }, error: null });
    const { signUpCustomer } = customerAuth;
    const res = await signUpCustomer('test@example.com', 'password', { name: 'Test' });
    expect(mockSignUp).toHaveBeenCalledWith({
      email: 'test@example.com',
      password: 'password',
      options: { data: { name: 'Test' } }
    });
    expect(res.data.user.id).toBe('123');
  });

  it('should restore session correctly', async () => {
    mockGetSession.mockResolvedValueOnce({ data: { session: { id: 'sess-1' } }, error: null });
    const { restoreCustomerSession } = customerAuth;
    const res = await restoreCustomerSession();
    expect(res.session.id).toBe('sess-1');
  });

  it('should sign in directly with email', async () => {
    mockSignInWithPassword.mockResolvedValueOnce({ data: { session: { id: 'sess-email' } }, error: null });
    const { signInCustomer } = customerAuth;
    const res = await signInCustomer('test@example.com', 'password');
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockSignInWithPassword).toHaveBeenCalledWith({
      email: 'test@example.com',
      password: 'password'
    });
    expect(res.data.session.id).toBe('sess-email');
  });

  it('should resolve username to email and then sign in', async () => {
    mockRpc.mockResolvedValueOnce({ data: 'resolved@example.com', error: null });
    mockSignInWithPassword.mockResolvedValueOnce({ data: { session: { id: 'sess-username' } }, error: null });
    const { signInCustomer } = customerAuth;
    const res = await signInCustomer('myusername', 'password');
    expect(mockRpc).toHaveBeenCalledWith('resolve_username_to_email', { p_username: 'myusername' });
    expect(mockSignInWithPassword).toHaveBeenCalledWith({
      email: 'resolved@example.com',
      password: 'password'
    });
    expect(res.data.session.id).toBe('sess-username');
  });

  it('should return error when username resolution fails', async () => {
    mockRpc.mockResolvedValueOnce({ data: null, error: null });
    const { signInCustomer } = customerAuth;
    const res = await signInCustomer('invalid_username', 'password');
    expect(mockRpc).toHaveBeenCalledWith('resolve_username_to_email', { p_username: 'invalid_username' });
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
    expect(res.error).toBeDefined();
    expect(res.error.message).toBe('Invalid login credentials');
  });
});
