-- =====================================================================
-- Supermarket POS - Supabase schema (multi-tenant + monthly subscription)
-- شغّل الملف كامل مرة واحدة في: Supabase Dashboard > SQL Editor > New query > Run
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1) الجداول الأساسية
-- ---------------------------------------------------------------------
create table if not exists public.stores (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  -- كود المحل: بيستخدمه عملاؤه للدخول على نسخة المحل في تطبيق العملاء
  code         text not null unique default substr(md5(gen_random_uuid()::text), 1, 8),
  brand_color  text not null default '#2E7D32',
  logo_url     text,
  created_at   timestamptz not null default now()
);

-- اشتراك شهري لكل سوبر ماركت. التجديد = تعديل active_until من لوحة Supabase.
create table if not exists public.subscriptions (
  store_id      uuid primary key references public.stores(id) on delete cascade,
  plan          text not null default 'monthly',
  status        text not null default 'trial' check (status in ('trial','active','suspended')),
  active_until  timestamptz not null,
  updated_at    timestamptz not null default now()
);

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  store_id    uuid references public.stores(id) on delete set null,
  full_name   text,
  role        text not null default 'owner' check (role in ('owner','manager','cashier')),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2) دوال مساعدة (security definer عشان نتفادى تكرار RLS)
-- ---------------------------------------------------------------------
create or replace function public.current_store_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select store_id from public.profiles where id = auth.uid()
$$;

-- الاشتراك فعّال لو لسه ماخلصش (+ 3 أيام سماح)
create or replace function public.store_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.subscriptions s
    where s.store_id = public.current_store_id()
      and s.status <> 'suspended'
      and s.active_until + interval '3 days' > now()
  )
$$;

-- ---------------------------------------------------------------------
-- 3) جداول البيانات (كل جدول فيه store_id)
-- ---------------------------------------------------------------------
create table if not exists public.products (
  id          uuid primary key,
  store_id    uuid not null default public.current_store_id() references public.stores(id) on delete cascade,
  name        text not null,
  barcode     text,
  price       numeric(12,2) not null default 0,
  cost        numeric(12,2) not null default 0,
  stock_qty   numeric(12,3) not null default 0,   -- بيتحدث بالـ trigger من stock_movements
  min_stock   numeric(12,3) not null default 0,
  active      boolean not null default true,
  updated_at  timestamptz not null default now(),
  unique (store_id, barcode)
);
create index if not exists idx_products_store on public.products(store_id);

create table if not exists public.sales (
  id              uuid primary key,
  store_id        uuid not null default public.current_store_id() references public.stores(id) on delete cascade,
  cashier_id      uuid default auth.uid(),
  total           numeric(12,2) not null,
  discount        numeric(12,2) not null default 0,
  payment_method  text not null default 'cash',
  created_at      timestamptz not null default now()
);
create index if not exists idx_sales_store_date on public.sales(store_id, created_at desc);

create table if not exists public.sale_items (
  id          uuid primary key,
  store_id    uuid not null default public.current_store_id() references public.stores(id) on delete cascade,
  sale_id     uuid not null references public.sales(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,
  qty         numeric(12,3) not null,
  price       numeric(12,2) not null,
  cost        numeric(12,2) not null default 0
);
create index if not exists idx_sale_items_sale on public.sale_items(sale_id);

-- دفتر حركة المخزون: كل تغيير في الكمية بيتسجل كحركة (آمن مع الأوفلاين)
create table if not exists public.stock_movements (
  id          uuid primary key,
  store_id    uuid not null default public.current_store_id() references public.stores(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  qty_delta   numeric(12,3) not null,
  reason      text not null check (reason in ('sale','purchase','adjustment','opening')),
  ref_id      uuid,
  created_at  timestamptz not null default now()
);
create index if not exists idx_movements_product on public.stock_movements(product_id);

create or replace function public.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products
     set stock_qty = stock_qty + new.qty_delta
   where id = new.product_id and store_id = new.store_id;
  return new;
end;
$$;

drop trigger if exists trg_apply_stock_movement on public.stock_movements;
create trigger trg_apply_stock_movement
after insert on public.stock_movements
for each row execute function public.apply_stock_movement();

-- ---------------------------------------------------------------------
-- 4) تسجيل سوبر ماركت جديد (تجربة 14 يوم)
-- ---------------------------------------------------------------------
create or replace function public.register_store(p_store_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and store_id is not null) then
    raise exception 'already has a store';
  end if;

  insert into public.stores(name) values (trim(p_store_name)) returning id into v_store;
  insert into public.subscriptions(store_id, status, active_until)
    values (v_store, 'trial', now() + interval '14 days');
  insert into public.profiles(id, store_id, role)
    values (auth.uid(), v_store, 'owner')
    on conflict (id) do update set store_id = excluded.store_id, role = 'owner';

  return v_store;
end;
$$;

revoke all on function public.register_store(text) from public;
grant execute on function public.register_store(text) to authenticated;

-- ---------------------------------------------------------------------
-- 4.5) كتالوج عام لتطبيق عملاء المحل (نسخة المحل الخاصة)
--      - بيرجع اسم المحل وألوانه ومنتجاته (الاسم والسعر وهل متوفر فقط).
--      - لا يكشف سعر التكلفة ولا الكمية الفعلية.
--      - لو اشتراك المحل خلص بيرجع status = 'suspended' وبدون منتجات،
--        فالنسخة بتقف عند العملاء فوراً من السيرفر.
-- ---------------------------------------------------------------------
create or replace function public.public_catalog(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_store  public.stores%rowtype;
  v_active boolean;
begin
  select * into v_store from public.stores where code = lower(trim(p_code));
  if not found then
    return jsonb_build_object('status', 'not_found');
  end if;

  select exists (
    select 1 from public.subscriptions s
    where s.store_id = v_store.id
      and s.status <> 'suspended'
      and s.active_until + interval '3 days' > now()
  ) into v_active;

  if not v_active then
    return jsonb_build_object('status', 'suspended', 'name', v_store.name);
  end if;

  return jsonb_build_object(
    'status', 'active',
    'store', jsonb_build_object(
      'name', v_store.name,
      'brand_color', v_store.brand_color,
      'logo_url', v_store.logo_url
    ),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', pr.id,
               'name', pr.name,
               'barcode', pr.barcode,
               'price', pr.price,
               'in_stock', pr.stock_qty > 0
             ) order by pr.name)
      from public.products pr
      where pr.store_id = v_store.id and pr.active
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.public_catalog(text) from public;
grant execute on function public.public_catalog(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Row Level Security
--    - القراءة دايماً متاحة لبيانات السوبر ماركت نفسه (حتى لو الاشتراك خلص)
--    - الكتابة مش متاحة إلا لو الاشتراك فعّال
-- ---------------------------------------------------------------------
alter table public.stores          enable row level security;
alter table public.subscriptions   enable row level security;
alter table public.profiles        enable row level security;
alter table public.products        enable row level security;
alter table public.sales           enable row level security;
alter table public.sale_items      enable row level security;
alter table public.stock_movements enable row level security;

drop policy if exists "own store read" on public.stores;
create policy "own store read" on public.stores
  for select to authenticated using (id = public.current_store_id());

drop policy if exists "own subscription read" on public.subscriptions;
create policy "own subscription read" on public.subscriptions
  for select to authenticated using (store_id = public.current_store_id());

drop policy if exists "own profile read" on public.profiles;
create policy "own profile read" on public.profiles
  for select to authenticated using (id = auth.uid());

-- products / sales / sale_items / stock_movements
do $$
declare t text;
begin
  foreach t in array array['products','sales','sale_items','stock_movements']
  loop
    execute format('drop policy if exists "tenant read" on public.%I', t);
    execute format('create policy "tenant read" on public.%I for select to authenticated using (store_id = public.current_store_id())', t);

    execute format('drop policy if exists "tenant insert" on public.%I', t);
    execute format('create policy "tenant insert" on public.%I for insert to authenticated with check (store_id = public.current_store_id() and public.store_active())', t);
  end loop;
end $$;

-- تعديل المنتجات فقط (المبيعات وحركات المخزون لا تُعدّل)
drop policy if exists "tenant update" on public.products;
create policy "tenant update" on public.products
  for update to authenticated
  using (store_id = public.current_store_id() and public.store_active())
  with check (store_id = public.current_store_id() and public.store_active());

-- منع تعديل stock_qty مباشرة من التطبيق (لازم يعدّي من stock_movements)
-- (الـ trigger بيشتغل بصلاحيات المالك فبيقدر يحدّث stock_qty عادي)
revoke insert, update on public.products from authenticated;
grant insert (id, name, barcode, price, cost, min_stock, active, updated_at)
  on public.products to authenticated;
grant update (id, name, barcode, price, cost, min_stock, active, updated_at)
  on public.products to authenticated;

-- ---------------------------------------------------------------------
-- 6) إدارة الاشتراكات (من عندك كأدمن)
--    من Table Editor > subscriptions عدّل active_until و status.
--    أو بالـ SQL:
--      update public.subscriptions
--         set active_until = active_until + interval '1 month', status = 'active'
--       where store_id = '<store uuid>';
-- ---------------------------------------------------------------------
