-- =====================================================================
-- 004: أدوات الأدمن للاشتراكات (تشغّلها إنت بس من Supabase SQL Editor)
-- آمن لو اتشغّل مرتين. مفيش أي تأثير على التطبيقات.
--
-- بعد التشغيل:
--   -- شوف كل المحلات وحالة اشتراكها (الأقرب للانتهاء الأول):
--   select * from public.admin_stores_overview();
--
--   -- جدّد اشتراك محل شهر (بالكود اللي في إعدادات تطبيق المحل):
--   select public.admin_renew_subscription('a1b2c3d4', 1);
--
--   -- أوقف محل أو رجّعه:
--   select public.admin_set_subscription_status('a1b2c3d4', 'suspended');
--   select public.admin_set_subscription_status('a1b2c3d4', 'active');
--
-- منطق الانتهاء (نفس السيرفر والتطبيقين): بعد active_until فيه 3 أيام سماح،
-- وبعدها: السيرفر بيرفض أي كتابة، تطبيق المحل بيتحول للقراءة فقط،
-- وتطبيق العملاء بيعرض "المتجر غير متاح".
-- =====================================================================

-- تجديد: لو الاشتراك لسه شغال بنزوّد على تاريخ الانتهاء الحالي،
-- ولو منتهي بنبدأ العدّ من النهارده. بيرجّع تاريخ الانتهاء الجديد.
create or replace function public.admin_renew_subscription(p_store_code text, p_months integer default 1)
returns timestamptz
language plpgsql
as $$
declare
  v_store uuid;
  v_until timestamptz;
begin
  if p_months is null or p_months < 1 or p_months > 36 then
    raise exception 'months must be between 1 and 36';
  end if;

  select id into v_store from public.stores where code = lower(trim(p_store_code));
  if v_store is null then
    raise exception 'store not found: %', p_store_code;
  end if;

  update public.subscriptions
     set active_until = greatest(active_until, now()) + make_interval(months => p_months),
         status = 'active',
         updated_at = now()
   where store_id = v_store
   returning active_until into v_until;

  if v_until is null then
    insert into public.subscriptions(store_id, status, active_until)
    values (v_store, 'active', now() + make_interval(months => p_months))
    returning active_until into v_until;
  end if;

  return v_until;
end;
$$;

-- تغيير الحالة: trial / active / suspended
create or replace function public.admin_set_subscription_status(p_store_code text, p_status text)
returns void
language plpgsql
as $$
declare
  v_store uuid;
begin
  if p_status is null or p_status not in ('trial', 'active', 'suspended') then
    raise exception 'status must be trial, active or suspended';
  end if;

  select id into v_store from public.stores where code = lower(trim(p_store_code));
  if v_store is null then
    raise exception 'store not found: %', p_store_code;
  end if;

  update public.subscriptions
     set status = p_status, updated_at = now()
   where store_id = v_store;
  if not found then
    raise exception 'store has no subscription row: %', p_store_code;
  end if;
end;
$$;

-- نظرة عامة: كل المحلات وحالتها (الأقرب للانتهاء الأول)
create or replace function public.admin_stores_overview()
returns table (
  store_name   text,
  store_code   text,
  sub_status   text,
  active_until timestamptz,
  days_left    integer,
  state        text
)
language sql
stable
as $$
  select st.name,
         st.code,
         sub.status,
         sub.active_until,
         ceil(extract(epoch from (sub.active_until - now())) / 86400)::integer,
         case
           when sub.store_id is null then 'بدون اشتراك'
           when sub.status = 'suspended' then 'موقوف'
           when now() < sub.active_until then 'نشط'
           when now() < sub.active_until + interval '3 days' then 'سماح'
           else 'منتهي'
         end
    from public.stores st
    left join public.subscriptions sub on sub.store_id = st.id
   order by sub.active_until asc nulls first;
$$;

-- الدوال دي للأدمن بس: ممنوعة على المستخدمين العاديين (RPC من التطبيقات)
revoke all on function public.admin_renew_subscription(text, integer) from public, anon, authenticated;
revoke all on function public.admin_set_subscription_status(text, text) from public, anon, authenticated;
revoke all on function public.admin_stores_overview() from public, anon, authenticated;
