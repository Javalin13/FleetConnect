import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = 'https://rreqjjrmvytnwnsidmqi.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJyZXFqanJtdnl0bnduc2lkbXFpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MjAxMzcsImV4cCI6MjA5Mzk5NjEzN30.q4M3A6Dix3F_9Im2pw8DUIeE4C-INtUlvImRDM58MTA';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export const customerAuth = {
    /**
     * Sign up a new customer
     */
    async signUpCustomer(email, password, metadata = {}) {
        const { data, error } = await supabase.auth.signUp({
            email,
            password,
            options: {
                data: metadata
            }
        });
        return { data, error };
    },

    /**
     * Sign in an existing customer
     */
    async signInCustomer(usernameOrEmail, password) {
        let email = usernameOrEmail;
        if (!usernameOrEmail.includes('@')) {
            const { data: resolvedEmail, error: rpcError } = await supabase.rpc('resolve_username_to_email', {
                p_username: usernameOrEmail
            });
            if (rpcError) {
                return { data: null, error: rpcError };
            }
            if (!resolvedEmail) {
                return { data: null, error: new Error('Invalid login credentials') };
            }
            email = resolvedEmail;
        }
        const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password
        });
        return { data, error };
    },

    /**
     * Sign out the current customer
     */
    async signOutCustomer() {
        const { error } = await supabase.auth.signOut();
        return { error };
    },

    /**
     * Trigger password reset email
     */
    async resetCustomerPassword(email) {
        const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
            redirectTo: `${window.location.origin}/reset-password.html`,
        });
        return { data, error };
    },

    /**
     * Update password (used in reset flow)
     */
    async updatePassword(newPassword) {
        const { data, error } = await supabase.auth.updateUser({
            password: newPassword
        });
        return { data, error };
    },

    /**
     * Restore session from persistence
     */
    async restoreCustomerSession() {
        const { data: { session }, error } = await supabase.auth.getSession();
        return { session, error };
    },

    /**
     * Get current user
     */
    async getCurrentUser() {
        const { data: { user } } = await supabase.auth.getUser();
        return user;
    }
};
