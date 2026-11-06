-- =====================================================================
-- 003: العميل يختار توصيل أو استلام من المحل (القرار D9)
-- شغّله بعد 002. آمن لو اتشغّل مرتين.
-- =====================================================================

-- 1) إعدادات المحل: تفعيل/تعطيل كل خيار (رسوم التوصيل موجودة من 002)
alter table public.stores add column if not exists delivery_enabled boolean not null default true;
alter table public.stores add column if not exists pickup_enabled   boolean not null default true;
grant update (delivery_enabled, pickup_enabled) on public.stores to authenticated;

-- 2) نوع الطلب. العنوان والموقع مطلوبين فقط لو توصيل
alter table public.orders add column if not exists fulfillment_type text not null default 'delivery';
alter table public.orders drop constraint if exists orders_fulfillment_type_check;
alter table public.orders add constraint orders_fulfillment_type_check
  check (fulfillment_type in ('delivery', 'pickup'));

alter table public.orders alter column address_text drop not null;
alter table public.orders alter column lat drop not null;
alter table public.orders alter column lng drop not null;

alter table public.orders drop constraint if exists orders_delivery_needs_location;
alter table public.orders add constraint orders_delivery_needs_location
  check (fulfillment_type <> 'delivery'
         or (address_text is not null and lat is not null and lng is not null));

-- 3) حالة جديدة: جاهز للاستلام (للاستلام من المحل)
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('new', 'preparing', 'out_for_delivery', 'ready_for_pickup', 'delivered', 'cancelled'));

create or replace function public.orders_before_update()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status then
    if not (
      (old.status = 'new'       and new.status in ('preparing', 'cancelled')) or
      (old.status = 'preparing' and new.status in ('out_for_delivery', 'ready_for_pickup', 'delivered', 'cancelled')) or
      (old.status in ('out_for_delivery', 'ready_for_pickup') and new.status in ('delivered', 'cancelled'))
    ) then
      raise exception 'invalid status transition % -> %', old.status, new.status;
    end if;
    if new.status = 'out_for_delivery' and new.fulfillment_type <> 'delivery' then
      raise exception 'pickup order cannot go out for delivery';
    end if;
    if new.status = 'ready_for_pickup' and new.fulfillment_type <> 'pickup' then
      raise exception 'delivery order cannot be ready for pickup';
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
  if old.status = 'new' and new.status in ('preparing', 'out_for_delivery', 'ready_for_pickup', 'delivered') then
    insert into public.stock_movements(id, store_id, product_id, qty_delta, reason, ref_id)
    select gen_random_uuid(), oi.store_id, oi.product_id, -oi.qty, 'sale', new.id
      from public.order_items oi
     where oi.order_id = new.id and oi.product_id is not null;
  end if;

  -- إلغاء بعد القبول: رجّع المخزون
  if old.status in ('preparing', 'out_for_delivery', 'ready_for_pickup') and new.status = 'cancelled' then
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

-- 4) إنشاء الطلب بنوعه (توصيل / استلام).
--    النسخة القديمة (8 معاملات) بتفضل موجودة كغلاف للتوصيل فقط (تحت)،
--    فتطبيق العملاء القديم مايتكسرش لو الـ migration اتشغّل قبل تحديثه.

create or replace function public.place_order(
  p_store_code      text,
  p_items           jsonb,
  p_fulfillment     text,
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
  v_fee      numeric := 0;
  v_total    numeric;
  v_delivery boolean;
  v_order    uuid := gen_random_uuid();
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_fulfillment is null or p_fulfillment not in ('delivery', 'pickup') then
    raise exception 'invalid fulfillment type';
  end if;
  v_delivery := (p_fulfillment = 'delivery');

  select * into v_store from public.stores where code = lower(trim(p_store_code));
  if not found then
    raise exception 'store not found';
  end if;

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
  if v_delivery and not v_store.delivery_enabled then
    raise exception 'delivery not available';
  end if;
  if (not v_delivery) and not v_store.pickup_enabled then
    raise exception 'pickup not available';
  end if;

  select * into v_cust from public.customers
   where user_id = auth.uid() and store_id = v_store.id;
  if not found then
    raise exception 'not a customer of this store';
  end if;

  if v_delivery then
    if p_lat is null or p_lng is null
       or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
      raise exception 'invalid location';
    end if;
    if coalesce(trim(p_address_text), '') = '' then
      raise exception 'address required';
    end if;
    v_fee := v_store.delivery_fee;
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty order';
  end if;

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
  v_total := v_subtotal + v_fee;

  insert into public.orders(
    id, store_id, customer_id, customer_name, customer_phone, fulfillment_type,
    address_text, address_details, lat, lng, accuracy_m,
    payment_method, note, subtotal, delivery_fee, total
  ) values (
    v_order, v_store.id, auth.uid(), v_cust.full_name, v_cust.phone, p_fulfillment,
    case when v_delivery then trim(p_address_text) end,
    case when v_delivery then nullif(trim(coalesce(p_address_details, '')), '') end,
    case when v_delivery then p_lat end,
    case when v_delivery then p_lng end,
    case when v_delivery then p_accuracy end,
    'cash', nullif(trim(coalesce(p_note, '')), ''), v_subtotal, v_fee, v_total
  );

  for v_item in select jsonb_array_elements(p_items) loop
    select * into v_prod from public.products where id = (v_item->>'product_id')::uuid;
    insert into public.order_items(order_id, store_id, product_id, name, qty, price, cost)
    values (v_order, v_store.id, v_prod.id, v_prod.name, (v_item->>'qty')::numeric, v_prod.price, v_prod.cost);
  end loop;

  return v_order;
end;
$$;

revoke all on function public.place_order(text, jsonb, text, text, text, double precision, double precision, double precision, text) from public;
grant execute on function public.place_order(text, jsonb, text, text, text, double precision, double precision, double precision, text) to authenticated;

-- غلاف للنسخة القديمة (من غير p_fulfillment): دايماً توصيل
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
begin
  return public.place_order(
    p_store_code, p_items, 'delivery',
    p_address_text, p_address_details, p_lat, p_lng, p_accuracy, p_note
  );
end;
$$;

revoke all on function public.place_order(text, jsonb, text, text, double precision, double precision, double precision, text) from public;
grant execute on function public.place_order(text, jsonb, text, text, double precision, double precision, double precision, text) to authenticated;

-- 5) الكتالوج العام: يضيف خيارات التوصيل/الاستلام
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
      'accepting_orders', v_store.accepting_orders,
      'delivery_enabled', v_store.delivery_enabled,
      'pickup_enabled', v_store.pickup_enabled
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
