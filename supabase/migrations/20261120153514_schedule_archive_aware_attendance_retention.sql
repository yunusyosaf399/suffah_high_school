
-- Enable Supabase Cron (pg_cron) for daily, archive-aware retention.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule(
  'suffah-attendance-retention',
  '15 2 * * *',
  'select private.purge_archived_attendance();'
);
-- Cron run logs otherwise grow indefinitely.
select cron.schedule(
  'suffah-cron-history-prune',
  '45 2 * * *',
  $$delete from cron.job_run_details
    where end_time < now() - interval '7 days';$$
);
