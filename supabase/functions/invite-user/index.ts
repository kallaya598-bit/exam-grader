import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { withSupabase } from 'jsr:@supabase/server@^1'

const APP_URL = 'https://kallaya598-bit.github.io/exam-grader/exam_grader.html'
const ALLOWED_ORIGINS = new Set([
  'https://kallaya598-bit.github.io',
  'http://localhost:8000',
  'http://127.0.0.1:8000',
])

function headers(req: Request) {
  const origin = req.headers.get('origin') || ''
  return {
    'Access-Control-Allow-Origin': ALLOWED_ORIGINS.has(origin) ? origin : 'https://kallaya598-bit.github.io',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
    'Vary': 'Origin',
  }
}

function reply(req: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: headers(req) })
}

const cleanEmail = (value: unknown) => String(value || '').trim().toLowerCase()
const cleanText = (value: unknown, max = 160) => String(value || '').trim().slice(0, max)

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: headers(req) })
    if (req.method !== 'POST') return reply(req, 405, { error: 'Method not allowed' })

    // Resolve the caller from Supabase Auth itself. This also keeps the
    // function compatible with both legacy and asymmetric JWT claim shapes.
    const { data: authData, error: authError } = await ctx.supabase.auth.getUser()
    const callerId = String(
      authData?.user?.id || ctx.userClaims?.id || ctx.jwtClaims?.sub || ''
    )
    if (authError || !callerId) return reply(req, 401, { error: 'Session expired' })
    const admin = ctx.supabaseAdmin

    let input: Record<string, unknown>
    try { input = await req.json() }
    catch { return reply(req, 400, { error: 'Invalid JSON' }) }

    const action = cleanText(input.action, 40)
    const email = cleanEmail(input.email)
    const fullName = cleanText(input.full_name)
    if (!email || !/^\S+@\S+\.\S+$/.test(email) || !fullName) {
      return reply(req, 400, { error: 'กรุณากรอกชื่อและอีเมลให้ถูกต้อง' })
    }

    if (action === 'create_school') {
      const { data: isPlatformAdmin, error: platformRoleError } = await ctx.supabase
        .rpc('exam_is_platform_admin')
      if (platformRoleError) return reply(req, 500, { error: 'ตรวจสอบสิทธิ์ผู้ดูแลระบบไม่สำเร็จ' })
      if (!isPlatformAdmin) return reply(req, 403, { error: 'เฉพาะผู้ดูแลระบบเท่านั้น' })

      const schoolName = cleanText(input.school_name, 200)
      const schoolCode = cleanText(input.school_code, 20).toUpperCase()
      if (!schoolName || !/^[A-Z0-9_-]{2,20}$/.test(schoolCode)) {
        return reply(req, 400, { error: 'ชื่อหรือรหัสโรงเรียนไม่ถูกต้อง' })
      }

      const { data: school, error: schoolError } = await admin
        .from('exam_schools').insert({ name: schoolName, code: schoolCode })
        .select('id,name,code').single()
      if (schoolError || !school) {
        return reply(req, schoolError?.code === '23505' ? 409 : 400, {
          error: schoolError?.code === '23505' ? 'รหัสโรงเรียนนี้ถูกใช้แล้ว' : 'สร้างโรงเรียนไม่สำเร็จ',
        })
      }

      const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { full_name: fullName, school_id: school.id, role: 'admin' },
        redirectTo: APP_URL,
      })
      if (inviteError || !invited.user) {
        await admin.from('exam_schools').delete().eq('id', school.id)
        return reply(req, 400, { error: inviteError?.message || 'ส่งคำเชิญไม่สำเร็จ' })
      }

      const { error: profileError } = await admin.from('exam_profiles').upsert({
        user_id: invited.user.id, school_id: school.id, email,
        full_name: fullName, role: 'admin',
      }, { onConflict: 'user_id' })
      if (profileError) {
        console.error('create_school profile error', profileError)
        await admin.from('exam_schools').delete().eq('id', school.id)
        return reply(req, 400, {
          error: `สร้างโปรไฟล์ผู้ดูแลไม่สำเร็จ (${profileError.code || 'database error'})`,
        })
      }
      return reply(req, 201, { ok: true, school, invited_email: email })
    }

    if (action === 'invite_teacher') {
      // Ask the same database helpers used by RLS. This avoids duplicating
      // role and tenant resolution in the Edge Function.
      const [roleResult, schoolResult] = await Promise.all([
        ctx.supabase.rpc('exam_is_school_admin'),
        ctx.supabase.rpc('exam_current_school_id'),
      ])
      if (roleResult.error || schoolResult.error) {
        return reply(req, 500, { error: 'ตรวจสอบสิทธิ์โรงเรียนไม่สำเร็จ' })
      }
      if (!roleResult.data || !schoolResult.data) {
        return reply(req, 403, { error: 'เฉพาะผู้ดูแลโรงเรียนเท่านั้น' })
      }
      const schoolId = String(schoolResult.data)

      const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { full_name: fullName, school_id: schoolId, role: 'teacher' },
        redirectTo: APP_URL,
      })
      if (inviteError || !invited.user) {
        return reply(req, 400, { error: inviteError?.message || 'ส่งคำเชิญไม่สำเร็จ' })
      }

      const { error: profileError } = await admin.from('exam_profiles').upsert({
        user_id: invited.user.id, school_id: schoolId, email,
        full_name: fullName, role: 'teacher',
      }, { onConflict: 'user_id' })
      if (profileError) {
        console.error('invite_teacher profile error', profileError)
        return reply(req, 400, {
          error: `สร้างโปรไฟล์ครูไม่สำเร็จ (${profileError.code || 'database error'})`,
        })
      }
      return reply(req, 201, { ok: true, invited_email: email })
    }

    return reply(req, 400, { error: 'Unknown action' })
  }),
}
