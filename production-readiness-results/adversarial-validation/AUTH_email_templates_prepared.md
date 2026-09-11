# Prepared Niswah-Branded Auth Email Templates (not yet applied)

Prepared per Wave 1 Closure Preparation §C. **Nothing in this file has been applied to production** — these are ready-to-paste values for Supabase Dashboard → Authentication → Email Templates, pending the same explicit authorization as the `site_url`/`uri_allow_list` change (`AUTH-001`).

Supabase templates are global (not per-recipient-locale), so each template below is bilingual in one email — Arabic first (the app's own default locale), English second — rather than picking one language and guessing wrong for the other half of users.

Only two auth email flows are actually reachable by current app code (confirmed via exhaustive `grep` — see Wave 1 report §0/reconciliation): **signup confirmation** and **password recovery**. Both use the same Supabase template variable, `{{ .ConfirmationURL }}`. Email-change, magic-link, and invite templates are also included below for completeness (the charter's §C asks to "at minimum inspect" all enabled flows) but are marked accordingly — Supabase enables the *capability* project-wide, but no current app code path ever triggers these three specifically (confirmed: no `updateUser(email:)` call — `updateProfile` writes directly to the `profiles` table instead, see the new finding below; no `signInWithOtp`; no `inviteUserByEmail`).

---

## 1. Signup confirmation — REACHABLE, launch-relevant

**Subject** (replaces default `Confirm your email address`):
```
تأكيدي بريدك الإلكتروني - نسوة | Confirm your email - Niswah
```

**HTML content** (replaces the current unmodified Supabase default):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تأكيدي بريدك الإلكتروني</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    اضغطي على الزر أدناه لتأكيد بريدكِ الإلكتروني وإتمام إنشاء حسابكِ في نسوة.
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 15px; display: inline-block;">تأكيد البريد الإلكتروني</a>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Confirm your email</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 20px;">
    Tap the button below to confirm your email address and finish creating your Niswah account.
  </p>
  <div style="text-align: center; margin: 0 0 8px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 11px 28px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 13px; display: inline-block;">Confirm Email</a>
  </div>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin-top: 28px; line-height: 1.6;">
    إذا لم تطلبي إنشاء هذا الحساب، يمكنكِ تجاهل هذه الرسالة بأمان.<br>
    If you didn't request this account, you can safely ignore this email.
  </p>
</div>
```

---

## 2. Password recovery — REACHABLE, launch-relevant

**Subject** (replaces default `Reset your password`):
```
إعادة تعيين كلمة المرور - نسوة | Reset your password - Niswah
```

**HTML content**:
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">إعادة تعيين كلمة المرور</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    وصلنا طلب لإعادة تعيين كلمة مرور حسابكِ. اضغطي على الزر أدناه لاختيار كلمة مرور جديدة.
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 15px; display: inline-block;">إعادة تعيين كلمة المرور</a>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Reset your password</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 20px;">
    We received a request to reset your account's password. Tap the button below to choose a new one.
  </p>
  <div style="text-align: center; margin: 0 0 8px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 11px 28px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 13px; display: inline-block;">Reset Password</a>
  </div>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin-top: 28px; line-height: 1.6;">
    إذا لم تطلبي إعادة تعيين كلمة المرور، يمكنكِ تجاهل هذه الرسالة بأمان.<br>
    If you didn't request a password reset, you can safely ignore this email.
  </p>
</div>
```

---

## 3. Email-change, magic-link, invite — NOT currently reachable, template branding optional

Confirmed via exhaustive `grep` of `lib/`:
- **Email-change**: no app code calls `auth.updateUser(email: ...)`. The Profile screen's "update email" instead writes directly to `public.profiles.email` — a column that **does not exist** on the live `profiles` table (see the new finding below). This confirmation flow is not reachable by any working app code today.
- **Magic link**: no app code calls `signInWithOtp`.
- **Invite**: no app code calls `inviteUserByEmail`.

Branding these three is low-priority (no real user will see them under current app behavior) but zero-risk to do at the same time as items 1-2 if convenient, for consistency should any of these be wired up in a future wave. Not included in detail here to keep this wave's deliverable focused on what's actually reachable.

---

## 4. Sender identity / custom SMTP

Unchanged from the prior wave's finding: `smtp_host`/`smtp_user`/`smtp_pass`/`smtp_admin_email`/`smtp_sender_name` are all `null` (re-confirmed live this wave). Until custom SMTP is configured, the From-address on both templates above will still show Supabase's own default sending domain, regardless of the HTML/subject branding — the visible *content* is fully Niswah-branded either way, but the sender identity is not.

**Owner action required, exact fields, no secrets requested here**: in Supabase Dashboard → Project Settings → Authentication → SMTP Settings, enter:
- **Sender email** — a real, deliverable address on a domain you control (a dedicated `noreply@` or `hello@` address is more conventional transactional practice than reusing `admin@niswah.app`, but that's your call, not an engineering one)
- **Sender name** — `Niswah` (or `نسوة`)
- **Host**, **Port**, **Username**, **Password** — issued by whichever transactional-email provider you choose (e.g. Resend, Postmark, SendGrid, Amazon SES). This session will never see or request these values.
