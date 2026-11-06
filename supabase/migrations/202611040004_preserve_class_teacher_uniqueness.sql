create unique index if not exists class_teacher_assignments_class_session_term_key
  on public.class_teacher_assignments (class_id, academic_session_id, term_id);
