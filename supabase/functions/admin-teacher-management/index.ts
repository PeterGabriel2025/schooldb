import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

const teacherRoles = new Set([
  'secondary_subject_teacher',
  'secondary_class_teacher',
  'primary_teacher',
  'nursery_teacher'
]);

const jsonResponse = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authorization = request.headers.get('Authorization');
  const accessToken = authorization?.replace(/^Bearer\s+/i, '');
  const projectUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!authorization || !accessToken || !projectUrl || !anonKey || !serviceRoleKey) {
    console.error('Teacher management function is missing authorization or server configuration.');
    return jsonResponse({ error: 'Teacher management is not configured.' }, 500);
  }

  const callerClient = createClient(projectUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const adminClient = createClient(projectUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const cleanupCreatedTeacher = async (teacherId: string) => {
    const { error: profileCleanupError } = await adminClient.from('profiles').delete().eq('id', teacherId);
    if (profileCleanupError) console.error('Could not clean up the teacher profile.', profileCleanupError);
    const { error: authCleanupError } = await adminClient.auth.admin.deleteUser(teacherId);
    if (authCleanupError) console.error('Could not clean up the Auth user.', authCleanupError);
  };
  const cleanupRecoveredTeacher = async (teacherId: string) => {
    const { error } = await adminClient.from('profiles').delete().eq('id', teacherId);
    if (error) console.error('Could not clean up the recovered teacher profile.', error);
  };

  const { data: userData, error: userError } = await callerClient.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return jsonResponse({ error: 'Sign in with an administrator account to continue.' }, 401);
  }
  const { data: callerProfile, error: profileError } = await callerClient
    .from('profiles')
    .select('role, is_active')
    .eq('id', userData.user.id)
    .maybeSingle();
  if (profileError) {
    console.error('Could not verify teacher-management permissions.', profileError);
    return jsonResponse({ error: 'Could not verify administrator permissions.' }, 500);
  }
  if (callerProfile?.role !== 'administrator' || !callerProfile.is_active) {
    return jsonResponse({ error: 'Only an active administrator can manage teacher accounts.' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'Request body must be valid JSON.' }, 400);
  }

  if (body.action === 'create') {
    const fullName = typeof body.full_name === 'string' ? body.full_name.trim() : '';
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    const classIds = Array.isArray(body.class_ids)
      ? body.class_ids.filter((value): value is string => typeof value === 'string')
      : [];
    const offeringIds = Array.isArray(body.offering_ids)
      ? body.offering_ids.filter((value): value is string => typeof value === 'string')
      : [];
    const academicSessionId = typeof body.academic_session_id === 'string' ? body.academic_session_id : '';
    const termId = typeof body.term_id === 'string' ? body.term_id : '';
    const roles = Array.isArray(body.roles)
      ? body.roles.filter((value): value is string => typeof value === 'string' && teacherRoles.has(value))
      : typeof body.role === 'string' && teacherRoles.has(body.role) ? [body.role] : [];
    const role = roles[0];
    if (fullName.length < 1 || fullName.length > 160 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
      || password.length < 8 || !roles.length) {
      return jsonResponse({ error: 'Enter a valid teacher name, email, password (at least 8 characters), and teacher role.' }, 400);
    }
    if ((classIds.length || offeringIds.length) && (!academicSessionId || !termId)) {
      return jsonResponse({ error: 'Select an academic session and term for the teacher assignment.' }, 400);
    }
    if (termId) {
      const { data: term, error: termError } = await adminClient
        .from('terms')
        .select('id, academic_session_id')
        .eq('id', termId)
        .maybeSingle();
      if (termError || !term || term.academic_session_id !== academicSessionId) {
        return jsonResponse({ error: 'The selected term does not belong to the selected academic session.' }, 400);
      }
    }
    if (offeringIds.length) {
      const { data: offerings, error: offeringsError } = await adminClient
        .from('class_subject_offerings')
        .select('id, academic_session_id')
        .in('id', [...new Set(offeringIds)]);
      if (offeringsError || (offerings || []).some((offering) => offering.academic_session_id !== academicSessionId)) {
        return jsonResponse({ error: 'Every subject assignment must belong to the selected academic session.' }, 400);
      }
    }

    const { data: existingUsers, error: listUsersError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000
    });
    if (listUsersError) {
      console.error('Could not check existing Auth users.', listUsersError);
      return jsonResponse({ error: 'Could not check whether this email already exists.' }, 500);
    }
    const existingUser = existingUsers.users.find((user) => user.email?.toLowerCase() === email);
    let teacherId = existingUser?.id;
    let createdAuthUser = false;
    if (existingUser) {
      const { data: existingProfile, error: profileLookupError } = await adminClient
        .from('profiles')
        .select('id, role')
        .eq('id', existingUser.id)
        .maybeSingle();
      if (profileLookupError) {
        console.error('Could not check the existing teacher profile.', profileLookupError);
        return jsonResponse({ error: 'Could not check the existing school profile.' }, 500);
      }
      if (existingProfile) {
        return jsonResponse({ error: 'This email already belongs to an existing school profile. Edit that teacher instead.' }, 409);
      }
      const { error: recoverError } = await adminClient.auth.admin.updateUserById(existingUser.id, {
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, role }
      });
      if (recoverError) {
        console.error('Could not recover the existing Auth account.', recoverError);
        return jsonResponse({ error: 'This email exists, but its account could not be recovered.' }, 400);
      }
    } else {
      const { data: createdUser, error: createUserError } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, role }
      });
      if (createUserError || !createdUser.user) {
        console.error('Teacher account creation failed.', createUserError);
        return jsonResponse({ error: createUserError?.message || 'Could not create the teacher account.' }, 400);
      }
      teacherId = createdUser.user.id;
      createdAuthUser = true;
    }
    if (!teacherId) {
      return jsonResponse({ error: 'Could not identify the teacher account.' }, 500);
    }

    const { error: createProfileError } = await adminClient.from('profiles').insert({
      id: teacherId,
      full_name: fullName,
      role,
      is_active: true,
      must_change_password: false
    });
    if (createProfileError) {
      if (createdAuthUser) {
        const { error: cleanupError } = await adminClient.auth.admin.deleteUser(teacherId);
        if (cleanupError) console.error('Could not clean up the Auth user after profile creation failed.', cleanupError);
      }
      console.error('Teacher profile creation failed.', createProfileError);
      return jsonResponse({ error: `Teacher account was created, but the school profile could not be saved: ${createProfileError.message}` }, 500);
    }

    const { error: roleError } = await adminClient.from('teacher_roles').insert(
      [...new Set(roles)].map((teacherRole) => ({ teacher_id: teacherId, role: teacherRole }))
    );
    if (roleError) {
      if (createdAuthUser) await cleanupCreatedTeacher(teacherId);
      else await cleanupRecoveredTeacher(teacherId);
      console.error('Teacher role grants after account creation failed.', roleError);
      return jsonResponse({ error: 'Teacher account was created, but the teacher roles could not be saved.' }, 500);
    }

    if (classIds.length) {
      const { error: classAssignmentError } = await adminClient.from('class_teacher_assignments').insert(
        [...new Set(classIds)].map((classId) => ({
          teacher_id: teacherId,
          class_id: classId,
          academic_session_id: academicSessionId,
          term_id: termId
        }))
      );
      if (classAssignmentError) {
        if (createdAuthUser) await cleanupCreatedTeacher(teacherId);
        else await cleanupRecoveredTeacher(teacherId);
        console.error('Class teacher assignments after account creation failed.', classAssignmentError);
        return jsonResponse({ error: `Teacher account could not be assigned to the selected classes: ${classAssignmentError.message}` }, 400);
      }
    }

    if (offeringIds.length) {
      const { error: subjectAssignmentError } = await adminClient.from('subject_teacher_assignments').insert(
        [...new Set(offeringIds)].map((offeringId) => ({
          teacher_id: teacherId,
          class_subject_offering_id: offeringId,
          term_id: termId
        }))
      );
      if (subjectAssignmentError) {
        if (createdAuthUser) await cleanupCreatedTeacher(teacherId);
        else await cleanupRecoveredTeacher(teacherId);
        console.error('Subject teacher assignments after account creation failed.', subjectAssignmentError);
        return jsonResponse({ error: `Teacher account could not be assigned to the selected subjects: ${subjectAssignmentError.message}` }, 400);
      }
    }

    return jsonResponse({ success: true, message: 'Teacher account created.' });
  }

  if (body.action === 'reset_password') {
    const teacherId = typeof body.teacher_id === 'string' ? body.teacher_id : '';
    const password = typeof body.password === 'string' ? body.password : '';
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(teacherId)
      || password.length < 8) {
      return jsonResponse({ error: 'Select a teacher and enter a password with at least 8 characters.' }, 400);
    }
    const { data: teacher, error: teacherError } = await adminClient
      .from('profiles')
      .select('id, role')
      .eq('id', teacherId)
      .maybeSingle();
    if (teacherError || !teacher || teacher.role === 'administrator') {
      return jsonResponse({ error: 'Only an existing teacher account can have its password changed.' }, 400);
    }
    const { error: passwordError } = await adminClient.auth.admin.updateUserById(teacherId, { password });
    if (passwordError) {
      console.error('Teacher password reset failed.', passwordError);
      return jsonResponse({ error: passwordError.message }, 400);
    }
    return jsonResponse({ success: true, message: 'Teacher password changed.' });
  }

  if (body.action === 'remove') {
    const teacherId = typeof body.teacher_id === 'string' ? body.teacher_id : '';
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(teacherId)) {
      return jsonResponse({ error: 'Select a valid teacher account.' }, 400);
    }
    if (teacherId === userData.user.id) {
      return jsonResponse({ error: 'You cannot remove your own administrator account here.' }, 400);
    }

    const { data: teacher, error: teacherError } = await adminClient
      .from('profiles')
      .select('id, role, full_name')
      .eq('id', teacherId)
      .maybeSingle();
    if (teacherError) {
      console.error('Could not load the teacher profile for removal.', teacherError);
      return jsonResponse({ error: 'Could not load the selected teacher.' }, 500);
    }
    if (!teacher || teacher.role === 'administrator') {
      return jsonResponse({ error: 'Only teacher accounts can be removed here.' }, 400);
    }

    const usageChecks = await Promise.all([
      adminClient.from('class_teacher_assignments').select('id', { count: 'exact', head: true }).eq('teacher_id', teacherId),
      adminClient.from('subject_teacher_assignments').select('id', { count: 'exact', head: true }).eq('teacher_id', teacherId),
      adminClient.from('result_component_scores').select('id', { count: 'exact', head: true }).eq('recorded_by', teacherId),
      adminClient.from('user_permission_overrides').select('id', { count: 'exact', head: true }).eq('granted_by', teacherId)
    ]);
    const usageError = usageChecks.find((result) => result.error);
    if (usageError?.error) {
      console.error('Could not verify whether the teacher account has historical references.', usageError.error);
      return jsonResponse({ error: 'Could not verify teacher history. No account changes were made.' }, 500);
    }
    const isReferenced = usageChecks.some((result) => (result.count || 0) > 0);
    if (isReferenced) {
      const { error: classAssignmentError } = await adminClient
        .from('class_teacher_assignments')
        .delete()
        .eq('teacher_id', teacherId);
      const { error: subjectAssignmentError } = await adminClient
        .from('subject_teacher_assignments')
        .delete()
        .eq('teacher_id', teacherId);
      if (classAssignmentError || subjectAssignmentError) {
        console.error('Could not remove teacher assignments before deactivation.', {
          classAssignmentError,
          subjectAssignmentError
        });
        return jsonResponse({ error: 'Could not remove this teacher from the active assignments.' }, 500);
      }
      const { error } = await callerClient.rpc('admin_deactivate_teacher', {
        p_teacher_id: teacherId
      });
      if (error) {
        console.error('Could not deactivate the referenced teacher account.', error);
        return jsonResponse({ error: 'Could not deactivate this teacher account.' }, 500);
      }
      return jsonResponse({ success: true, outcome: 'removed' });
    }

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(teacherId);
    if (deleteError) {
      console.error('Could not delete the unused teacher account.', deleteError);
      return jsonResponse({ error: 'Could not delete this teacher account.' }, 500);
    }
    return jsonResponse({ success: true, outcome: 'deleted' });
  }

  return jsonResponse({ error: 'Choose a supported teacher-management action.' }, 400);
});
