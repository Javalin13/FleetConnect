begin;

-- 1. Add username column to public.customers if it does not exist
alter table public.customers add column if not exists username text;

-- 2. Create the trigger function to automatically assign usernames
create or replace function public.ensure_customer_username()
returns trigger as $$
declare
  v_base_username text;
  v_clean_username text;
  v_suffix int := 1;
  v_exists boolean;
begin
  -- Only generate if username is not set
  if new.username is null or trim(new.username) = '' then
    -- Try to clean the name first (remove non-alphanumeric)
    v_base_username := regexp_replace(new.name, '[^a-zA-Z0-9]', '', 'g');

    -- If cleaning name results in empty, try email prefix
    if v_base_username is null or v_base_username = '' then
      v_base_username := regexp_replace(split_part(new.email, '@', 1), '[^a-zA-Z0-9]', '', 'g');
    end if;

    -- Fallback to 'user' if still empty
    if v_base_username is null or v_base_username = '' then
      v_base_username := 'user';
    end if;

    v_clean_username := v_base_username;

    -- Loop to find a unique username
    loop
      select exists (
        select 1
          from public.customers
         where lower(username) = lower(v_clean_username)
           and id <> new.id
      ) into v_exists;

      if not v_exists then
        exit;
      end if;

      v_clean_username := v_base_username || v_suffix;
      v_suffix := v_suffix + 1;
    end loop;

    new.username := v_clean_username;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- 3. Create the BEFORE INSERT OR UPDATE trigger on public.customers
drop trigger if exists tr_ensure_customer_username on public.customers;
create trigger tr_ensure_customer_username
before insert or update on public.customers
for each row
execute function public.ensure_customer_username();

-- 4. Automatically assign usernames to existing customers where missing
update public.customers set username = null where username is null;

-- 5. Add unique and not null constraints to the username column
alter table public.customers alter column username set not null;
alter table public.customers drop constraint if exists customers_username_unique;
alter table public.customers add constraint customers_username_unique unique (username);

-- 6. Create RPC function to resolve username to email
create or replace function public.resolve_username_to_email(p_username text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email
    from public.customers
   where lower(username) = lower(trim(p_username))
   limit 1;

  return v_email;
end;
$$;

-- 7. Grant execution to anonymous and authenticated users
revoke all on function public.resolve_username_to_email(text) from public;
grant execute on function public.resolve_username_to_email(text) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
