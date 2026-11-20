
-- Suffah High School: offline-first v1.
-- Only small, shared, durable records live in Postgres.
-- Local-only documents, report PDFs, full attendance archives and caches are excluded.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.app_users (
  user_id uuid primary key references auth.users(id) on delete restrict,
  role text not null check (role in ('owner','admin','teacher','accountant','clerk')),
  display_name text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create function private.has_role(allowed text[]) returns boolean
language sql stable security definer set search_path = ''
as $$
 select auth.uid() is not null and exists (
   select 1 from public.app_users u
   where u.user_id = auth.uid() and u.active and u.role = any(allowed)
 );
$$;
revoke all on function private.has_role(text[]) from public, anon;
grant execute on function private.has_role(text[]) to authenticated;

create table public.school_settings (
  id smallint primary key default 1 check (id = 1),
  name text not null,
  phone text,
  address text,
  time_zone text not null default 'Asia/Karachi',
  updated_at timestamptz not null default now()
);

create table public.academic_years (
  id smallint generated always as identity primary key,
  label text not null unique,
  starts_on date not null,
  ends_on date not null,
  check (starts_on < ends_on)
);

create table public.classes (
  id smallint generated always as identity primary key,
  label text not null unique,
  sort_order smallint not null default 0
);

create table public.subjects (
  id smallint generated always as identity primary key,
  name text not null unique
);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  employee_no text not null unique,
  full_name text not null,
  phone text,
  designation text,
  auth_user_id uuid unique references public.app_users(user_id) on delete set null,
  joined_on date,
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.teacher_assignments (
  staff_id uuid not null references public.staff(id),
  class_id smallint not null references public.classes(id),
  academic_year_id smallint not null references public.academic_years(id),
  primary key (staff_id, class_id, academic_year_id)
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  admission_no text not null unique,
  full_name text not null,
  guardian_name text not null,
  guardian_phone text,
  date_of_birth date,
  admitted_on date not null default current_date,
  gender char(1) check (gender in ('M','F','X')),
  photo_path text,
  status text not null default 'active'
    check (status in ('active','graduated','withdrawn','transferred')),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint student_photo_fixed_path check (
    photo_path is null or photo_path = id::text || '.webp'
  )
);

create table public.student_enrollments (
  student_id uuid not null references public.students(id),
  academic_year_id smallint not null references public.academic_years(id),
  class_id smallint not null references public.classes(id),
  roll_no text,
  enrolled_on date,
  left_on date,
  transport_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (student_id, academic_year_id),
  check (left_on is null or enrolled_on is null or left_on >= enrolled_on)
);

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  academic_year_id smallint not null references public.academic_years(id),
  class_id smallint not null references public.classes(id),
  subject_id smallint references public.subjects(id),
  title text not null,
  kind text not null check (kind in ('test','exam','final')),
  held_on date,
  maximum_marks numeric(7,2) not null check (maximum_marks > 0),
  updated_at timestamptz not null default now()
);

create table public.assessment_marks (
  assessment_id uuid not null references public.assessments(id),
  student_id uuid not null references public.students(id),
  obtained_marks numeric(7,2),
  absent boolean not null default false,
  note text,
  updated_at timestamptz not null default now(),
  primary key (assessment_id, student_id),
  check (obtained_marks is null or obtained_marks >= 0),
  check (not absent or obtained_marks is null)
);

-- Small, shared text only; large attachments and generated PDFs remain local.
create table public.school_content (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in (
    'notice','homework','diary','syllabus','task','timetable',
    'date_sheet','question_reference','download_reference','message'
  )),
  class_id smallint references public.classes(id),
  student_id uuid references public.students(id),
  title text not null,
  body text not null default '' check (char_length(body) <= 4000),
  scheduled_on date,
  created_by uuid references public.app_users(user_id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.school_assets (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('library','equipment','stock')),
  item_code text unique,
  name text not null,
  quantity integer not null default 0 check (quantity >= 0),
  notes text,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Standard recurring fees are calculated from rates + enrollment.
-- Exceptional charges, payments and discounts are durable ledger entries.
create table public.fee_rates (
  id integer generated always as identity primary key,
  academic_year_id smallint not null references public.academic_years(id),
  class_id smallint not null references public.classes(id),
  fee_code text not null,
  effective_from date not null,
  frequency text not null check (frequency in ('monthly','once')),
  amount_paisa bigint not null check (amount_paisa >= 0),
  unique (academic_year_id, class_id, fee_code, effective_from)
);

create table public.finance_entries (
  id uuid primary key default gen_random_uuid(),
  entry_kind text not null check (entry_kind in (
    'fee_charge','fee_payment','fee_discount','fee_refund',
    'expense','income','canteen_sale','stationery_sale'
  )),
  occurred_on date not null,
  student_id uuid references public.students(id),
  staff_id uuid references public.staff(id),
  fee_code text,
  billing_month date,
  category text,
  receipt_no text,
  amount_paisa bigint not null check (amount_paisa > 0),
  note text,
  created_by uuid not null references public.app_users(user_id),
  created_at timestamptz not null default now(),
  constraint fee_period_first_day check (
    billing_month is null or extract(day from billing_month) = 1
  )
);

-- Remote attendance is TEMPORARY. Desktop archives are authoritative.
create table public.student_attendance (
  student_id uuid not null references public.students(id),
  attendance_date date not null,
  class_id smallint not null references public.classes(id),
  status char(1) not null check (status in ('P','A','L','H')),
  recorded_by uuid not null references public.app_users(user_id),
  updated_at timestamptz not null default now(),
  primary key (student_id, attendance_date)
);

create table public.staff_attendance (
  staff_id uuid not null references public.staff(id),
  attendance_date date not null,
  status char(1) not null check (status in ('P','A','L','H')),
  recorded_by uuid not null references public.app_users(user_id),
  updated_at timestamptz not null default now(),
  primary key (staff_id, attendance_date)
);

-- Desktop writes one signed-off receipt per fully archived attendance date.
-- A more recent change to an attendance row invalidates the old receipt for that row.
create table public.attendance_archive_receipts (
  attendance_date date primary key,
  archive_sha256 char(64) not null
    check (archive_sha256 ~ '^[a-fA-F0-9]{64}$'),
  device_label text not null,
  archived_by uuid not null references public.app_users(user_id),
  archived_at timestamptz not null default now()
);

create index on public.student_enrollments (academic_year_id, class_id);
create index on public.teacher_assignments (class_id, academic_year_id);
create index on public.students (updated_at);
create index on public.staff (updated_at);
create index on public.school_content (updated_at);
create index on public.school_content (class_id, kind);
create index on public.finance_entries (student_id, occurred_on);
create index on public.finance_entries (occurred_on, entry_kind);
create index on public.student_attendance (attendance_date);
create index on public.staff_attendance (attendance_date);

create function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'school_settings','staff','students','student_enrollments',
    'assessments','assessment_marks','school_content','school_assets',
    'student_attendance','staff_attendance'
  ]
  loop
    execute format('create trigger touch_updated_at before update on public.%I for each row execute function private.touch_updated_at()',table_name);
  end loop;
end;
$$;

-- Teacher access is limited to assigned classes in the active academic year.
create function private.can_teach_class(target_class smallint)
returns boolean language sql stable security definer set search_path = ''
as $$
 select auth.uid() is not null and (
   private.has_role(array['owner','admin']) or
   (
    private.has_role(array['teacher']) and exists (
     select 1 from public.teacher_assignments ta
       join public.staff s on s.id = ta.staff_id
       join public.academic_years y on y.id = ta.academic_year_id
     where ta.class_id = target_class and s.auth_user_id = auth.uid()
       and s.active and y.starts_on <= current_date and y.ends_on >= current_date
    )
   )
 );
$$;

create function private.can_read_student(target_student uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
 select auth.uid() is not null and (
   private.has_role(array['owner','admin','accountant','clerk'])
   or (private.has_role(array['teacher']) and exists (
      select 1 from public.student_enrollments e
      join public.teacher_assignments ta
        on ta.class_id = e.class_id and ta.academic_year_id = e.academic_year_id
      join public.academic_years y on y.id = e.academic_year_id
      join public.staff s on s.id = ta.staff_id
      where e.student_id = target_student and s.auth_user_id = auth.uid()
        and s.active and y.starts_on <= current_date and y.ends_on >= current_date
   ))
 );
$$;
revoke all on function private.can_teach_class(smallint), private.can_read_student(uuid) from public, anon;
grant execute on function private.can_teach_class(smallint), private.can_read_student(uuid) to authenticated;

-- RLS: owner can administer all rows; nobody has anonymous Data API access.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'app_users','school_settings','academic_years','classes','subjects',
    'staff','teacher_assignments','students','student_enrollments',
    'assessments','assessment_marks','school_content','school_assets',
    'fee_rates','finance_entries','student_attendance','staff_attendance',
    'attendance_archive_receipts'
  ]
  loop
    execute format('alter table public.%I enable row level security',table_name);
    execute format(
       'create policy %I on public.%I for all to authenticated using ((select private.has_role(array[''owner'']::text[]))) with check ((select private.has_role(array[''owner'']::text[])))',
       table_name || '_owner', table_name
    );
  end loop;
end;
$$;

create policy "user_read_self" on public.app_users for select to authenticated
using (user_id = (select auth.uid()));
create policy "settings_read" on public.school_settings for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])));
create policy "year_read" on public.academic_years for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])));
create policy "class_read" on public.classes for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])));
create policy "subject_read" on public.subjects for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])));
create policy "staff_read" on public.staff for select to authenticated
using ((select private.has_role(array['admin','accountant'])) or auth_user_id = (select auth.uid()));
create policy "student_read" on public.students for select to authenticated
using ((select private.can_read_student(id)));
create policy "enrollment_read" on public.student_enrollments for select to authenticated
using ((select private.has_role(array['admin','accountant','clerk'])) or private.can_teach_class(class_id));
create policy "assignment_read" on public.teacher_assignments for select to authenticated
using ((select private.has_role(array['admin'])) or exists (
 select 1 from public.staff s where s.id = staff_id and s.auth_user_id = (select auth.uid())
));
create policy "assessment_read" on public.assessments for select to authenticated
using (private.can_teach_class(class_id));
create policy "marks_read" on public.assessment_marks for select to authenticated
using (exists (select 1 from public.assessments a where a.id=assessment_id and private.can_teach_class(a.class_id)));
create policy "content_read" on public.school_content for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])) and
       (student_id is null or private.can_read_student(student_id)));
create policy "assets_read" on public.school_assets for select to authenticated
using ((select private.has_role(array['admin','teacher','accountant','clerk'])));
create policy "fee_rates_read" on public.fee_rates for select to authenticated
using ((select private.has_role(array['admin','accountant','clerk'])));
create policy "finances_read" on public.finance_entries for select to authenticated
using ((select private.has_role(array['admin','accountant'])));
create policy "finance_insert" on public.finance_entries for insert to authenticated
with check ((select private.has_role(array['admin','accountant','clerk']))
           and created_by = (select auth.uid()));
create policy "attendance_student_read" on public.student_attendance for select to authenticated
using (private.can_teach_class(class_id));
create policy "attendance_student_insert" on public.student_attendance for insert to authenticated
with check (private.can_teach_class(class_id) and recorded_by = (select auth.uid()));
create policy "attendance_student_update" on public.student_attendance for update to authenticated
using (private.can_teach_class(class_id))
with check (private.can_teach_class(class_id));
create policy "attendance_staff_read" on public.staff_attendance for select to authenticated
using ((select private.has_role(array['admin'])));
create policy "archive_receipts_read" on public.attendance_archive_receipts for select to authenticated
using ((select private.has_role(array['admin'])));
create policy "archive_receipts_insert" on public.attendance_archive_receipts for insert to authenticated
with check ((select private.has_role(array['admin'])) and archived_by = (select auth.uid()));
create policy "archive_receipts_update" on public.attendance_archive_receipts for update to authenticated
using ((select private.has_role(array['admin'])))
with check ((select private.has_role(array['admin'])) and archived_by = (select auth.uid()));

-- Admin can maintain non-financial school records (not delete audit ledger).
do $$
declare table_name text;
begin
 foreach table_name in array array[
   'school_settings','academic_years','classes','subjects','staff',
   'teacher_assignments','students','student_enrollments',
   'assessments','assessment_marks','school_content','school_assets',
   'fee_rates','student_attendance','staff_attendance'
 ]
 loop
   execute format('create policy %I on public.%I for all to authenticated using ((select private.has_role(array[''admin'']::text[]))) with check ((select private.has_role(array[''admin'']::text[])))',
    table_name || '_admin', table_name);
 end loop;
end;
$$;

create policy "teacher_assessments_insert" on public.assessments for insert to authenticated
with check (private.can_teach_class(class_id));
create policy "teacher_assessments_update" on public.assessments for update to authenticated
using (private.can_teach_class(class_id)) with check (private.can_teach_class(class_id));
create policy "teacher_marks_insert" on public.assessment_marks for insert to authenticated
with check (exists (select 1 from public.assessments a where a.id=assessment_id and private.can_teach_class(a.class_id)));
create policy "teacher_marks_update" on public.assessment_marks for update to authenticated
using (exists (select 1 from public.assessments a where a.id=assessment_id and private.can_teach_class(a.class_id)))
with check (exists (select 1 from public.assessments a where a.id=assessment_id and private.can_teach_class(a.class_id)));
create policy "teacher_content_insert" on public.school_content for insert to authenticated
with check ((select private.has_role(array['teacher'])) and class_id is not null
 and private.can_teach_class(class_id) and created_by=(select auth.uid())
 and kind in ('homework','diary','syllabus','task','message'));
create policy "teacher_content_update" on public.school_content for update to authenticated
using ((select private.has_role(array['teacher'])) and private.can_teach_class(class_id)
 and created_by=(select auth.uid()))
with check ((select private.has_role(array['teacher'])) and private.can_teach_class(class_id)
 and created_by=(select auth.uid()));

revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- User has already created an Auth account. Give only that existing user owner rights.
insert into public.app_users (user_id, role, display_name)
select id, 'owner', 'School Owner' from auth.users
where lower(email) = 'blog.younas@gmail.com'
on conflict (user_id) do nothing;
insert into public.school_settings (id,name)
values (1, 'Suffah High School')
on conflict (id) do nothing;

-- Only one private Storage bucket. No documents, PDFs or attachments here.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('student-photos', 'student-photos', false, 102400, array['image/webp'])
on conflict (id) do nothing;

create policy "suffah_photo_read" on storage.objects for select to authenticated
using (bucket_id='student-photos'
   and private.has_role(array['owner','admin','clerk']));
create policy "suffah_photo_insert" on storage.objects for insert to authenticated
with check (bucket_id='student-photos'
   and private.has_role(array['owner','admin','clerk'])
   and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$'
   and exists (select 1 from public.students s where s.id::text || '.webp'=name));
create policy "suffah_photo_update" on storage.objects for update to authenticated
using (bucket_id='student-photos' and private.has_role(array['owner','admin','clerk']))
with check (bucket_id='student-photos' and private.has_role(array['owner','admin','clerk']));
create policy "suffah_photo_delete" on storage.objects for delete to authenticated
using (bucket_id='student-photos' and private.has_role(array['owner','admin']));

-- Never purge unarchived or more recently modified attendance.
create function private.purge_archived_attendance()
returns void language plpgsql set search_path = '' as $$
begin
 delete from public.student_attendance a
 using public.attendance_archive_receipts r
 where a.attendance_date = r.attendance_date
   and a.attendance_date < (current_date - 30)
   and r.archived_at >= a.updated_at;
 delete from public.staff_attendance a
 using public.attendance_archive_receipts r
 where a.attendance_date = r.attendance_date
   and a.attendance_date < (current_date - 30)
   and r.archived_at >= a.updated_at;
end;
$$;
revoke all on function private.purge_archived_attendance() from public, anon, authenticated;
