# Niswah-Branded Auth Email Templates

Originally prepared per Wave 1 Closure Preparation §C; templates 1-2 applied to production during the `AUTH-001 Production Closure` wave (2026-09-12). Extended to templates 3-6 during the `Email Template Standardization` wave (2026-09-13). Extended to the final templates 7-13 during the `Final Email Template Completeness Pass` (2026-09-13, later the same day) per explicit owner instruction — **all 13 Supabase auth/security email templates are now standardized and applied to production.** Template 1 (Confirm Signup) remains the canonical visual-design reference throughout.

Supabase templates are global (not per-recipient-locale), so each template below is bilingual in one email — Arabic first (the app's own default locale), English second — rather than picking one language and guessing wrong for the other half of users.

**Reachability, re-verified 2026-09-13** (exhaustive `grep` of `lib/`, see Wave 1 report): only **signup confirmation** (`signUp`) and **password recovery request** (`resetPasswordForEmail`) are triggered by any current app code. Specifically:
- No app code calls `auth.updateUser(email: ...)` — the Profile screen's "update email" writes directly to a `profiles.email` column that does not exist on the live table. **Email change is not a working feature today.**
- No app code calls `auth.updateUser(password: ...)`, and **no screen in the app completes the password-recovery flow** (no "set new password" screen consumes the recovery deep link) — a distinct, previously undocumented functional gap, flagged here for a future wave, not fixed in this one (out of scope for email-template standardization).
- No app code calls `signInWithOtp`, `inviteUserByEmail`, phone-based auth, `linkIdentity`/`unlinkIdentity`, or any MFA enrollment API.

**All 13 templates are now branded and applied to production, even though 11 of the 13 are currently unreachable by any app code path** — this was zero-risk (a template with no code path that triggers it can never be shown to a real user) and was explicitly requested for full visual/copy consistency, so correct, on-brand bilingual content is already in place if/when the underlying app functionality (email change, in-app password change, magic link, invitations, phone auth, identity linking, MFA) is ever built. **No corresponding app feature or Supabase provider/auth capability was enabled anywhere in this process** — only `mailer_subjects_*`/`mailer_templates_*` content fields were ever touched, confirmed via a keyed check of every field in every payload applied across both waves.

---

## 1. Signup confirmation — REACHABLE, launch-relevant, canonical visual reference

**Subject**:
```
تأكيدي بريدك الإلكتروني - نسوة | Confirm your email - Niswah
```

**HTML content** (as applied live; a standardized bilingual footer was appended during the Email Template Standardization wave, 2026-09-13):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تأكيد بريدك الإلكتروني</h2>
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
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 2. Password recovery — REACHABLE, launch-relevant

**Subject**:
```
إعادة تعيين كلمة المرور - نسوة | Reset your password - Niswah
```

**HTML content** (as applied live; standardized footer appended):
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
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 3. Email address change confirmation — NOT reachable by app code, applied anyway (zero-risk, brand-ready)

Supabase variables used: `{{ .ConfirmationURL }}`, `{{ .NewEmail }}` (both present in Supabase's own default template for this type — none fabricated).

**Subject**: `تأكيد تغيير بريدك الإلكتروني - نسوة | Confirm your new email - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تأكيد تغيير البريد الإلكتروني</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    طلبتِ تغيير البريد الإلكتروني المرتبط بحسابك في نسوة. اضغطي على الزر أدناه لتأكيد عنوان البريد الإلكتروني الجديد.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    البريد الإلكتروني الجديد: {{ .NewEmail }}
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 15px; display: inline-block;">تأكيد البريد الجديد</a>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Confirm your new email</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    You requested to change the email address associated with your Niswah account. Tap the button below to confirm your new email address.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    New email address: {{ .NewEmail }}
  </p>
  <div style="text-align: center; margin: 0 0 8px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 11px 28px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 13px; display: inline-block;">Confirm New Email</a>
  </div>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin-top: 28px; line-height: 1.6;">
    إذا لم تطلبي هذا التغيير، يمكنكِ تجاهل هذه الرسالة بأمان.<br>
    If you didn't request this change, you can safely ignore this email.
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 4. Reauthentication — NOT reachable by app code (no MFA/reauth flow implemented), applied anyway

Supabase variable: `{{ .Token }}` (a numeric OTP code — this template type never uses `{{ .ConfirmationURL }}`). Rendered as a single shared code block between the Arabic and English sections rather than duplicating a CTA per language, since the code itself is not language-specific — the one deliberate structural adaptation from the confirmation/recovery pattern.

**Subject**: `رمز التحقق {{ .Token }} - نسوة | Your code {{ .Token }} - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تأكيد هويتك</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    لحماية حسابك في نسوة، نحتاج إلى التأكد من هويتك قبل تنفيذ هذا الإجراء الحساس. استخدمي رمز التحقق أدناه لإكمال العملية.
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <div style="display: inline-block; background-color: #FFF1F2; border: 1px solid #FECDD3; border-radius: 12px; padding: 16px 32px;">
      <span style="font-size: 28px; font-weight: 700; letter-spacing: 6px; color: #9F1239;">{{ .Token }}</span>
    </div>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Verify your identity</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 20px;">
    To protect your Niswah account, we need to verify your identity before completing this sensitive action. Use the verification code below to continue.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin-top: 8px; line-height: 1.6;">
    إذا لم تطلبي هذا الرمز، يمكنكِ تجاهل هذه الرسالة بأمان.<br>
    If you didn't request this code, you can safely ignore this email.
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 5. Password changed notification — NOT reachable (no in-app password change, no recovery-completion screen), applied anyway

Purely informational; Supabase's default template for this type carries no variables, and none were added.

**Subject**: `تم تغيير كلمة المرور - نسوة | Your password was changed - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تم تغيير كلمة المرور</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    تم تغيير كلمة المرور الخاصة بحسابك في نسوة بنجاح.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، فننصحكِ بتأمين حسابك فورًا والتواصل مع دعم نسوة.
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Your password was changed</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    The password for your Niswah account was successfully changed.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account immediately and contact Niswah support.
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 24px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 6. Email address changed notification — NOT reachable (email change is not a working feature), applied anyway

Supabase variables used: `{{ .OldEmail }}`, `{{ .Email }}` (both present in Supabase's own default template for this type).

**Subject**: `تم تغيير بريدك الإلكتروني - نسوة | Your email was changed - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تم تغيير بريدك الإلكتروني</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تم تغيير عنوان البريد الإلكتروني المرتبط بحسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك والتواصل مع دعم نسوة فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    من {{ .OldEmail }} إلى {{ .Email }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Your email address was changed</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    The email address associated with your Niswah account has been changed.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, please secure your account and contact Niswah support immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    From {{ .OldEmail }} to {{ .Email }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 8px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 7. Magic link / OTP — NOT reachable (no `signInWithOtp` call), applied anyway (2026-09-13)

Supabase variable: `{{ .ConfirmationURL }}` only (the default template for this type carries no separate OTP-code variable).

**Subject**: `تسجيل الدخول إلى نسوة | Sign in to Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تسجيل الدخول إلى نسوة</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    استخدمي الرابط أو رمز التحقق أدناه لتسجيل الدخول إلى حسابك في نسوة. إذا لم تطلبي تسجيل الدخول، يمكنك تجاهل هذه الرسالة.
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 15px; display: inline-block;">تسجيل الدخول</a>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Sign in to Niswah</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 20px;">
    Use the link or verification code below to sign in to your Niswah account. If you did not request this sign-in, you can ignore this email.
  </p>
  <div style="text-align: center; margin: 0 0 8px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 11px 28px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 13px; display: inline-block;">Sign In</a>
  </div>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 8. Invite user — NOT reachable (no `inviteUserByEmail` call), applied anyway (2026-09-13)

Supabase variable: `{{ .ConfirmationURL }}` only.

**Subject**: `دعوة للانضمام إلى نسوة | You're invited to Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">دعوة للانضمام إلى نسوة</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 24px;">
    تمت دعوتك لإنشاء حساب في نسوة. اضغطي على الزر أدناه لقبول الدعوة وإكمال إنشاء حسابك.
  </p>
  <div style="text-align: center; margin: 0 0 28px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 14px 36px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 15px; display: inline-block;">قبول الدعوة</a>
  </div>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">You're invited to Niswah</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 20px;">
    You've been invited to create a Niswah account. Tap the button below to accept the invitation and complete your account.
  </p>
  <div style="text-align: center; margin: 0 0 8px;">
    <a href="{{ .ConfirmationURL }}" style="background-color: #E11D48; color: #ffffff; padding: 11px 28px; border-radius: 12px; text-decoration: none; font-weight: 700; font-size: 13px; display: inline-block;">Accept Invitation</a>
  </div>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 9. Phone number changed — NOT reachable (no phone auth in app), applied anyway (2026-09-13)

Supabase variables: `{{ .OldPhone }}`, `{{ .Phone }}` (both present in Supabase's own default for this type).

**Subject**: `تم تغيير رقم الهاتف - نسوة | Your phone number was changed - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تم تغيير رقم الهاتف</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تم تغيير رقم الهاتف المرتبط بحسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك والتواصل مع دعم نسوة فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    من {{ .OldPhone }} إلى {{ .Phone }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">Your phone number was changed</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    The phone number associated with your Niswah account has been changed.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account and contact Niswah support immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    From {{ .OldPhone }} to {{ .Phone }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 10. Sign-in method linked — NOT reachable (no identity-linking flow; Google OAuth disabled), applied anyway (2026-09-13)

Supabase variables: `{{ .Provider }}`, `{{ .Email }}`.

**Subject**: `تم ربط طريقة تسجيل دخول جديدة - نسوة | A new sign-in method was linked - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تم ربط طريقة جديدة لتسجيل الدخول</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تم ربط طريقة جديدة لتسجيل الدخول بحسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    {{ .Provider }} — {{ .Email }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">A new sign-in method was linked</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    A new sign-in method was linked to your Niswah account.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    {{ .Provider }} — {{ .Email }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 11. Sign-in method removed — NOT reachable, applied anyway (2026-09-13)

Supabase variables: `{{ .Provider }}`, `{{ .Email }}`.

**Subject**: `تمت إزالة طريقة تسجيل الدخول - نسوة | A sign-in method was removed - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تمت إزالة طريقة لتسجيل الدخول</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تمت إزالة إحدى طرق تسجيل الدخول من حسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    {{ .Provider }} — {{ .Email }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">A sign-in method was removed</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    A sign-in method was removed from your Niswah account.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    {{ .Provider }} — {{ .Email }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 12. MFA method added — NOT reachable (no MFA enrollment implemented), applied anyway (2026-09-13)

Supabase variable: `{{ .FactorType }}`.

**Subject**: `تمت إضافة وسيلة تحقق - نسوة | A new MFA method was added - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تمت إضافة وسيلة تحقق إضافية</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تمت إضافة وسيلة جديدة للتحقق متعدد العوامل إلى حسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    {{ .FactorType }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">A new MFA method was added</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    A new multi-factor authentication method was added to your Niswah account.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    {{ .FactorType }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 13. MFA method removed — NOT reachable, applied anyway (2026-09-13)

Supabase variable: `{{ .FactorType }}`.

**Subject**: `تمت إزالة وسيلة تحقق - نسوة | An MFA method was removed - Niswah`

**HTML content** (applied live):
```html
<div style="font-family: -apple-system, 'Segoe UI', Tahoma, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px 24px; color: #1F2937;">
  <div style="text-align: center; margin-bottom: 24px;">
    <div style="font-size: 28px; font-weight: 700; color: #9F1239;">نسوة</div>
    <div style="font-size: 12px; color: #9CA3AF; letter-spacing: 2px; margin-top: 2px;">NISWAH</div>
  </div>
  <h2 style="text-align: center; font-size: 19px; color: #1F2937; margin: 0 0 8px;">تمت إزالة وسيلة تحقق إضافية</h2>
  <p style="text-align: center; color: #4B5563; font-size: 14px; line-height: 1.7; margin: 0 0 8px;">
    تمت إزالة وسيلة من وسائل التحقق متعدد العوامل من حسابك في نسوة.<br><br>
    إذا كنتِ أنتِ من أجريتِ هذا التغيير، فلا يلزم اتخاذ أي إجراء.<br><br>
    إذا لم تكوني أنتِ، يرجى تأمين حسابك فورًا.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 12px; margin: 0 0 24px;">
    {{ .FactorType }}
  </p>
  <hr style="border: none; border-top: 1px solid #F3F4F6; margin: 0 0 24px;">
  <h3 style="text-align: center; font-size: 15px; color: #1F2937; margin: 0 0 6px;">An MFA method was removed</h3>
  <p style="text-align: center; color: #4B5563; font-size: 13px; line-height: 1.6; margin: 0 0 8px;">
    A multi-factor authentication method was removed from your Niswah account.<br><br>
    If you made this change, no action is required.<br><br>
    If you did not make this change, secure your account immediately.
  </p>
  <p style="text-align: center; color: #9CA3AF; font-size: 11px; margin: 0 0 20px;">
    {{ .FactorType }}
  </p>
  <p style="text-align: center; color: #D1D5DB; font-size: 10px; margin: 16px 0 0; line-height: 1.6;">
    نسوة | Niswah<br>
    تم إرسال هذه الرسالة تلقائيًا لأغراض أمان الحساب. يرجى عدم مشاركة روابط أو رموز التحقق مع أي شخص.<br>
    This email was sent automatically for account security. Never share verification links or codes with anyone.
  </p>
</div>
```

---

## 14. Sender identity / custom SMTP

**Observed change since the prior wave, not acted on in this pass**: `smtp_host` is no longer `null` — it now reads `mail.spacemail.com`, indicating the owner has begun (or completed) SMTP setup independently since the last wave. `smtp_user`/`smtp_pass`/other SMTP fields were not inspected further (out of scope — this pass is template-content-only and explicitly excludes touching SMTP config; `smtp_pass` in particular is a secret field and was never queried). This is noted here for visibility only; it does not change `AUTH-001`'s status, and per this pass's explicit instruction no AUTH-001 E4 verification was performed.

**Owner action required, exact fields, no secrets requested here**: in Supabase Dashboard → Project Settings → Authentication → SMTP Settings, enter:
- **Sender email** — a real, deliverable address on a domain you control (a dedicated `noreply@` or `hello@` address is more conventional transactional practice than reusing `admin@niswah.app`, but that's your call, not an engineering one)
- **Sender name** — `Niswah` (or `نسوة`)
- **Host**, **Port**, **Username**, **Password** — issued by whichever transactional-email provider you choose (e.g. Resend, Postmark, SendGrid, Amazon SES). This session will never see or request these values.
