-- =====================================================================
-- 002: العملاء + العناوين + الطلبات أونلاين
-- شغّل الملف كامل في Supabase > SQL Editor (بعد schema.sql). آمن لو اتشغّل مرتين.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) إعدادات الطلبات على مستوى المحل
-- ---------------------------------------------------------------------
alter table public.stores add column if not exists phone text;
alter table public.stores add column if not exists delivery_fee numeric(12,2) not null default 0;
alter table public.stores add column if not exists min_order numeric(12,2) not null default 0;
alter table public.stores add column if not exists accepting_orders boolean not null default true;

-- صاحب المحل يعدّل إعدادات محله فقط (الاشتراك لازم يكون فعّال)
drop policy if exists "own store update" on public.stores;
create policy "own store update" on public.stores
  for update to authenticated
  using (id = public.current_store_id() and public.store_active())
  with check (id = public.current_store_id());

revoke update on public.stores from authenticated;
grant update (name, phone, brand_color, logo_url, delivery_fee, min_order, accepting_orders)
  on public.stores to authenticated;

-- ---------------------------------------------------------------------
-- 2) العملاء (مسجّلين بإيميل وكلمة مرور، وكل عميل تابع لمحل)
-- ---------------------------------------------------------------------
create table if not exists public.customers (
  user_id     uuid not null references auth.users(id) on delete cascade,
  store_id    uuid not null references public.stores(id) on delete cascade,
  full_name   text not null,
  phone       text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, store_id)
);

create table if not exists public.customer_addresses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  store_id     uuid not null references public.stores(id) on delete cascade,
  label        text not null default 'البيت',
  address_text text not null,
  details      text,                                   -- عمارة / دور / شقة / علامة مميزة
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  accuracy_m   double precision,                       -- دقة GPS بالمتر (null = اتحدد يدوياً على الخريطة)
  created_at   timestamptz not null default now()
);
create index if not exists idx_addresses_user on public.customer_addresses(user_id, store_id);

alter table public.customers          enable row level security;
alter table public.customer_addresses enable row level security;

drop policy if exists "own customer rows" on public.customers;
create policy "own customer rows" on public.customers
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "own addresses" on public.customer_addresses;
create policy "own addresses" on public.customer_addresses
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.customers c
                where c.user_id = auth.uid() and c.store_id = customer_addresses.store_id)
  );

revoke all on public.customers          from anon;
revoke all on public.customer_addresses from anon;
revoke insert, update, delete on public.customers from authenticated;

-- تسجيل العميل في محل (بيتم بعد إنشاء الحساب)
create or replace function public.register_customer(p_store_code text, p_full_name text, p_phone text)
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
  select id into v_store from public.stores where code = lower(trim(p_store_code));
  if v_store is null then
    raise exception 'store not found';
  end if;
  if coalesce(trim(p_full_name), '') = '' or coalesce(trim(p_phone), '') = '' then
    raise exception 'name and phone required';
  end if;

  insert into public.customers(user_id, store_id, full_name, phone)
  values (auth.uid(), v_store, trim(p_full_name), trim(p_phone))
  on conflict (user_id, store_id)
  do update set full_name = excluded.full_name, phone = excluded.phone;

  return v_store;
end;
$$;

revoke all on function public.register_customer(text, text, text) from public;
grant execute on function public.register_customer(text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3) الطلبات
-- ---------------------------------------------------------------------
create table if not exists public.orders (
  id               uuid primary key default gen_random_uuid(),
  store_id         uuid not null references public.stores(id) on delete cascade,
  customer_id      uuid not null references auth.users(id),
  customer_name    text not null,
  customer_phone   text not null,
  address_text     text not null,
  address_details  text,
  lat              double precision not null,
  lng              double precision not null,
  accuracy_m       double precision,
  payment_method   text not null default 'cash',
  note             text,
  subtotal         numeric(12,2) not null,
  delivery_fee     numeric(12,2) not null default 0,
  total            numeric(12,2) not null,
  status           text not null default 'new'
                   check (status in ('new','preparing','out_for_delivery','delivered','cancelled')),
  cancel_reason    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_orders_store_status on public.orders(store_id, status, created_at desc);
create index if not exists idx_orders_customer on public.orders(customer_id, created_at desc);

create table if not exists public.order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  store_id    uuid not null references public.stores(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,
  qty         numeric(12,3) not null check (qty > 0),
  price       numeric(12,2) not null,
  cost        numeric(12,2) not null default 0
);
create index if not exists idx_order_items_order on public.order_items(order_id);

alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

revoke all on public.orders      from anon;
revoke all on public.order_items from anon;
revoke insert, update, delete on public.orders      from authenticated;
revoke insert, update, delete on public.order_items from authenticated;
-- صاحب المحل يغيّر الحالة فقط
grant update (status, cancel_reason) on public.orders to authenticated;

-- قراءة: صاحب المحل بيشوف طلبات محله، والعميل بيشوف طلباته هو
drop policy if exists "staff read orders" on public.orders;
create policy "staff read orders" on public.orders
  for select to authenticated using (store_id = public.current_store_id());

drop policy if exists "customer read own orders" on public.orders;
create policy "customer read own orders" on public.orders
  for select to authenticated using (customer_id = auth.uid());

drop policy if exists "staff update orders" on public.orders;
create policy "staff update orders" on public.orders
  for update to authenticated
  using (store_id = public.current_store_id() and public.store_active())
  with check (store_id = public.current_store_id());

drop policy if exists "staff read order items" on public.order_items;
create policy "staff read order items" on public.order_items
  for select to authenticated using (store_id = public.current_store_id());

drop policy if exists "customer read own order items" on public.order_items;
create policy "customer read own order items" on public.order_items
  for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_items.order_id and o.customer_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 4) إنشاء الطلب: كل التحقق والأسعار من السيرفر (العميل ما يقدرش يتلاعب بالسعر)
-- ---------------------------------------------------------------------
create or replace function public.place_order(
  p_store_code      text,
  p_items           jsonb,
  p_address_text    text,
  p_address_details text,
  p_lat             double precision,
  p_lng             double precision,
  p_accuracy        double precision,
  p_note            text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store    public.stores%rowtype;
  v_cust     public.customers%rowtype;
  v_prod     public.products%rowtype;
  v_item     jsonb;
  v_qty      numeric;
  v_subtotal numeric := 0;
  v_total    numeric;
  v_order    uuid := gen_random_uuid();
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_store from public.stores where code = lower(trim(p_store_code));
  if not found then
    raise exception 'store not found';
  end if;

  -- الاشتراك لازم يكون فعّال
  if not exists (
    select 1 from public.subscriptions s
    where s.store_id = v_store.id
      and s.status <> 'suspended'
      and s.active_until + interval '3 days' > now()
  ) then
    raise exception 'store suspended';
  end if;

  if not v_store.accepting_orders then
    raise exception 'store not accepting orders';
  end if;

  select * into v_cust from public.customers
   where user_id = auth.uid() and store_id = v_store.id;
  if not found then
    raise exception 'not a customer of this store';
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'invalid location';
  end if;
  if coalesce(trim(p_address_text), '') = '' then
    raise exception 'address required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty order';
  end if;

  -- 1) تحقق من كل صنف وحساب الإجمالي من الأسعار الحقيقية
  for v_item in select jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'invalid quantity';
    end if;
    select * into v_prod from public.products
     where id = (v_item->>'product_id')::uuid and store_id = v_store.id and active;
    if not found then
      raise exception 'product unavailable';
    end if;
    if v_prod.stock_qty < v_qty then
      raise exception 'insufficient stock: %', v_prod.name;
    end if;
    v_subtotal := v_subtotal + v_prod.price * v_qty;
  end loop;

  if v_subtotal < v_store.min_order then
    raise exception 'below minimum order';
  end if;
  v_total := v_subtotal + v_store.delivery_fee;

  insert into public.orders(
    id, store_id, customer_id, customer_name, customer_phone,
    address_text, address_details, lat, lng, accuracy_m,
    payment_method, note, subtotal, delivery_fee, total
  ) values (
    v_order, v_store.id, auth.uid(), v_cust.full_name, v_cust.phone,
    trim(p_address_text), nullif(trim(coalesce(p_address_details, '')), ''), p_lat, p_lng, p_accuracy,
    'cash', nullif(trim(coalesce(p_note, '')), ''), v_subtotal, v_store.delivery_fee, v_total
  );

  -- 2) بنود الطلب
  for v_item in select jsonb_array_elements(p_items) loop
    select * into v_prod from public.products where id = (v_item->>'product_id')::uuid;
    insert into public.order_items(order_id, store_id, product_id, name, qty, price, cost)
    values (v_order, v_store.id, v_prod.id, v_prod.name, (v_item->>'qty')::numeric, v_prod.price, v_prod.cost);
  end loop;

  return v_order;
end;
$$;

revoke all on function public.place_order(text, jsonb, text, text, double precision, double precision, double precision, text) from public;
grant execute on function public.place_order(text, jsonb, text, text, double precision, double precision, double precision, text) to authenticated;

-- العميل يلغي طلبه طالما لسه "جديد"
create or replace function public.cancel_my_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
     set status = 'cancelled', cancel_reason = 'cancelled by customer'
   where id = p_order_id and customer_id = auth.uid() and status = 'new';
  if not found then
    raise exception 'cannot cancel';
  end if;
end;
$$;

revoke all on function public.cancel_my_order(uuid) from public;
grant execute on function public.cancel_my_order(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5) تغيير حالة الطلب: ترتيب مسموح + حجز المخزون + تسجيل البيع عند التسليم
-- ---------------------------------------------------------------------
create or replace function public.orders_before_update()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'new'              and new.status in ('preparing', 'cancelled')) or
      (old.status = 'preparing'        and new.status in ('out_for_delivery', 'delivered', 'cancelled')) or
      (old.status = 'out_for_delivery' and new.status in ('delivered', 'cancelled'))
    ) then
      raise exception 'invalid status transition % -> %', old.status, new.status;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.orders_after_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  -- أول ما الطلب يتقبل: حجز المخزون
  if old.status = 'new' and new.status in ('preparing', 'out_for_delivery', 'delivered') then
    insert into public.stock_movements(id, store_id, product_id, qty_delta, reason, ref_id)
    select gen_random_uuid(), oi.store_id, oi.product_id, -oi.qty, 'sale', new.id
      from public.order_items oi
     where oi.order_id = new.id and oi.product_id is not null;
  end if;

  -- إلغاء بعد القبول: رجّع المخزون
  if old.status in ('preparing', 'out_for_delivery') and new.status = 'cancelled' then
    insert into public.stock_movements(id, store_id, product_id, qty_delta, reason, ref_id)
    select gen_random_uuid(), oi.store_id, oi.product_id, oi.qty, 'adjustment', new.id
      from public.order_items oi
     where oi.order_id = new.id and oi.product_id is not null;
  end if;

  -- تم التسليم: يتسجل كعملية بيع (للتقارير)
  if new.status = 'delivered' then
    insert into public.sales(id, store_id, cashier_id, total, discount, payment_method, created_at)
    values (new.id, new.store_id, null, new.total, 0, 'cash', now())
    on conflict (id) do nothing;

    insert into public.sale_items(id, store_id, sale_id, product_id, name, qty, price, cost)
    select gen_random_uuid(), oi.store_id, new.id, oi.product_id, oi.name, oi.qty, oi.price, oi.cost
      from public.order_items oi
     where oi.order_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_orders_before_update on public.orders;
create trigger trg_orders_before_update
before update on public.orders
for each row execute function public.orders_before_update();

drop trigger if exists trg_orders_after_update on public.orders;
create trigger trg_orders_after_update
after update on public.orders
for each row execute function public.orders_after_update();

-- ---------------------------------------------------------------------
-- 6) تحديث الكتالوج العام: بيانات المحل + شروط التوصيل
--    (لو الاشتراك خلص بيرجع suspended: نسخة العملاء بتقف)
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
      'id', v_store.id,
      'name', v_store.name,
      'brand_color', v_store.brand_color,
      'logo_url', v_store.logo_url,
      'phone', v_store.phone,
      'delivery_fee', v_store.delivery_fee,
      'min_order', v_store.min_order,
      'accepting_orders', v_store.accepting_orders
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
-- 7) تنبيه فوري لصاحب المحل (Realtime) على الطلبات الجديدة
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end $$;
