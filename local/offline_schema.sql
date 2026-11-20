-- Local encrypted SQLite schema; configure SQLCipher encryption in Flutter
-- with an OS-protected key BEFORE opening this database.
pragma foreign_keys=on;
pragma journal_mode=wal;
pragma secure_delete=on;

create table if not exists cached_rows (
 user_id text not null,
 entity text not null,
 row_id text not null,
 payload_json text not null,
 server_updated_at text,
 cached_at text not null,
 deleted integer not null default 0 check(deleted in (0,1)),
 primary key(user_id,entity,row_id)
);
create index if not exists idx_cached_updates on cached_rows(user_id,entity,server_updated_at,row_id);

create table if not exists sync_cursors (
 user_id text not null,
 entity text not null,
 server_updated_at text,
 last_row_id text,
 last_sync_at text,
 primary key(user_id,entity)
);

create table if not exists pending_operations (
 operation_id text primary key,
 user_id text not null,
 entity text not null,
 row_id text not null,
 operation text not null check(operation in ('insert','update','delete')),
 payload_json text not null,
 base_updated_at text,
 queued_at text not null,
 status text not null default 'pending' check(status in ('pending','retry','conflict')),
 retries integer not null default 0,
 last_error text
);
create index if not exists idx_pending on pending_operations(user_id,status,queued_at);

create table if not exists attendance_archive (
 person_kind text not null check(person_kind in ('student','staff')),
 person_id text not null,
 attendance_date text not null,
 class_id integer,
 status text not null check(status in ('P','A','L','H')),
 remote_updated_at text not null,
 archived_at text not null,
 primary key(person_kind,person_id,attendance_date)
);
create index if not exists idx_archive_date on attendance_archive(attendance_date,person_kind);

create table if not exists attendance_archive_manifests (
 attendance_date text primary key,
 sha256 text not null,
 backup_verified_at text not null,
 acknowledgment_uploaded_at text
);

create table if not exists student_document_index (
 document_id text primary key,
 student_id text not null,
 document_type text not null,
 encrypted_relative_path text not null unique,
 ciphertext_sha256 text not null,
 file_bytes integer not null check(file_bytes>=0),
 created_at text not null
);
create index if not exists idx_documents_student on student_document_index(student_id);

create table if not exists local_file_index (
 file_id text primary key,
 kind text not null,
 encrypted_relative_path text not null unique,
 created_at text not null
);
