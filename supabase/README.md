# Supabase database setup

This folder contains the initial database migrations for EduResults. They create
the relational schema, row-level security policies, assignment-based access
checks, configurable assessment components, result calculations, lifecycle
operations, tie-aware class standings, and audit records.

## Apply the migration

1. Create a Supabase project.
2. Install the Supabase CLI. Run `supabase init` from the project root if a
   `supabase\config.toml` file does not exist, then link this folder to the
   project.
3. Review the SQL migrations, then apply them with `supabase db push` or the
   Supabase SQL editor. The school setup and administrator-management
   migrations add the setup, assessment, score-saving, and safe-removal
   functions required by the UI.
4. Create the first administrator profile from a trusted server-side process.
   Do not expose a service-role key in browser code or commit it to source control.
5. Deploy the secure administrator-managed teacher account function with
   `npx supabase functions deploy admin-teacher-management`. Administrators
   create teacher accounts with an initial password. Administrators
   can change a teacher password from the teacher edit dialog; passwords are stored
   only as secure Supabase Auth hashes and cannot be viewed later.
6. Create classes, sessions, terms, teacher assignments, and section assessment
   schemes before adding subjects or entering result data.

The migrations do not create real users, school records, or credentials. The
UI login uses Supabase Auth and requires an active `public.profiles` row
matching the signed-in user's Auth ID. The dashboard metrics, session/class
setup, student register, score entry, master sheets, and individual result
views use live Supabase data. The administrator configures CA, Test, and Exam
once for each school section (secondary, primary, nursery); that shared scheme
applies to every subject, class, and academic session in the section. Add
subjects by school level and session: for example, adding a subject to Senior
Secondary adds it to active SSS 1, SSS 2, and SSS 3 classes in that session
with one action. The same applies to Junior Secondary, Upper Basic, Lower Basic,
Nursery, and Pre-nursery.
Updating a section scheme creates a new scheme version for all offerings, so
past results retain the components they were recorded against. Scheme updates
are blocked while that section has draft results. The administrator can also
edit classes, subject offerings, academic sessions, grading bands, teacher
profiles, and assignments after the management migrations are applied.
Classes, sessions, and subject offerings with dependent school records are
archived rather than destructively removed. Teacher accounts use the trusted
`admin-teacher-management` Edge Function; referenced teacher accounts are
deactivated so their history remains intact.
Class-teacher assignments grant access to the assigned class master sheet only.
Subject-teacher assignments grant score entry and editing only for the selected
subject/class offerings. Having both roles does not grant class-wide score
editing.

The remaining report cards (missing scores, class summaries, submission
monitoring, and audit activity) and result review/approval controls are not
connected to live data. Permission administration is persisted and enforced
through the live permission override functions.

## Important boundaries

- All application tables have row-level security enabled.
- Teacher access is scoped by class and subject assignments; explicit permission
  overrides are administrator-managed.
- Active non-administrator teachers can hold both class-teacher and
  subject-teacher assignments using the same account. Administrators remain
  excluded from teacher assignments.
- Administrators can grant multiple teacher roles and assign multiple classes
  or subject offerings to one teacher account.
- `register_student` creates a student and their class enrollment atomically,
  checks the caller's class-register permission, and writes an audit event.
- Score component values are checked against the configured maximum in the
  database.
- Teachers can edit draft results for assigned subjects; score edits are blocked
  for submitted, approved, and locked results.
- Result submission requires every required assessment component. Missing scores
  are not silently counted as zero.
- Database functions calculate totals, grades, averages, and competition ranks;
  incomplete students are not ranked.
- Approval, locking, and reopening a locked result for correction are
  administrator-only transitions. Reopening requires a recorded reason.
- Audit records are append-only to normal authenticated users and are visible
  only to administrators.
- Class/subject management writes and profile updates are administrator-only
  in row-level security, not just hidden in the interface.
- Section assessment settings are administrator-managed. New results must use
  the current section scheme, while existing results retain their historical
  assessment scheme and scores.
- New setup and management migrations must be pushed before using their
  functions. The teacher-management Edge Function must also be deployed before
  inviting or removing teacher accounts.

After applying the migrations and deploying the Edge Function, create an
academic session and classes in **Sessions & Settings**, configure the
secondary, primary, and nursery assessment schemes once each, invite teachers,
add subjects to classes, configure assignments, and register students before
entering scores. Score saving and submission are enforced by database
permissions. The function deployment and migration push are separate steps.

Primary and Nursery use the shared 1st Assessment (20), 2nd Assessment (20),
and Examination (60) scheme. Their subject average is the subject total divided
by the three components, and class average is the average of those subject
averages. Class positions are ranked from the highest class average to the
lowest; Secondary standings retain their existing calculation.
