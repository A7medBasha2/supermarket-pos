# Supermarket POS

تطبيق إدارة سوبر ماركت (Flutter + Supabase) بيشتغل **أوفلاين** ويتزامن مع السيرفر لما النت يرجع.
كل سوبر ماركت له حساب واشتراك شهري، وبيانات كل محل معزولة عن التاني.

## الإعداد من الموبايل (بدون كمبيوتر)

### 1) قاعدة البيانات (Supabase)
1. اعمل مشروع جديد مجاني على supabase.com.
2. **SQL Editor ← New query**: الصق محتوى الملف `supabase/schema.sql` كامل واضغط **Run**.
3. **Authentication ← Providers ← Email**: عطّل **Confirm email** (للتجربة الأولى).
4. **Project Settings ← API**: انسخ **Project URL** و **anon / publishable key**.

### 2) ربط التطبيق (GitHub Secrets)
في الريبو: **Settings ← Secrets and variables ← Actions ← New repository secret**، وأضف:

| الاسم | القيمة |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | anon / publishable key |

### 3) بناء ملف APK
1. تبويب **Actions ← Build Android APK ← Run workflow**.
2. استنى لحد ما يخلص (حوالي 5-10 دقايق)، وافتح التشغيل ونزّل الـ Artifact اسمه `supermarket-pos-apk`.
3. فك الضغط ونزّل `app-release.apk` وثبّته على الموبايل (فعّل التثبيت من مصادر غير معروفة).

لو البناء فشل: افتح اللوج وابعت نص الخطأ.

## الاشتراكات (من عندك كأدمن)
كل محل جديد بياخد **تجربة 14 يوم**. للتجديد شهرياً من **SQL Editor**:

```sql
update public.subscriptions
   set active_until = greatest(active_until, now()) + interval '1 month',
       status = 'active'
 where store_id = (select id from public.stores where name = 'اسم المحل');
```

لإيقاف محل: `update public.subscriptions set status = 'suspended' where store_id = '...';`

لما الاشتراك ينتهي (بعد 3 أيام سماح):
- السيرفر بيرفض أي كتابة (بيع / تعديل منتجات).
- التطبيق بيتحول للقراءة فقط وبيمنع البيع.
- الكتالوج العام لعملاء المحل بيوقف (`public_catalog` بيرجع `suspended`).

## الحالة
- [x] قاعدة البيانات + RLS + الاشتراكات
- [x] تطبيق الإدارة: مخزون، بيع (POS) بالباركود، تقارير، أوفلاين + مزامنة
- [ ] تطبيق العملاء (نسخة كل محل بكود المحل)
- [ ] تجديد تلقائي عبر بوابة دفع
- [ ] صلاحيات الموظفين (كاشير / مدير) وإضافتهم من التطبيق
- [ ] تقارير مجمّعة من كل الأجهزة (حالياً التقارير من مبيعات الجهاز نفسه)
