
-- Preserve finance history: corrections are append-only reversal entries.
alter table public.finance_entries
  add column reversal_of uuid unique references public.finance_entries(id);
alter table public.finance_entries drop constraint finance_entries_entry_kind_check;
alter table public.finance_entries
  add constraint finance_entries_entry_kind_check check (entry_kind in (
    'fee_charge','fee_payment','fee_discount','fee_refund','expense',
    'income','canteen_sale','stationery_sale','reversal'
  ));
alter table public.finance_entries
  add constraint reversal_requires_original check (
    (entry_kind = 'reversal') = (reversal_of is not null)
  );
create function private.guard_finance_entries() returns trigger
language plpgsql set search_path='' as $$
begin
  if TG_OP in ('UPDATE','DELETE') then
    raise exception 'Finance entries are immutable. Insert a reversal instead.';
  end if;
  if new.entry_kind = 'reversal' and not exists (
    select 1 from public.finance_entries f
    where f.id = new.reversal_of and f.entry_kind <> 'reversal'
      and f.amount_paisa = new.amount_paisa
  ) then
    raise exception 'Reversal must reference a non-reversal entry of the same value.';
  end if;
  return new;
end;
$$;
create trigger guard_finance_entries before insert or update or delete
on public.finance_entries for each row execute function private.guard_finance_entries();

-- Upserts may not change a photo into an arbitrary path.
drop policy "suffah_photo_update" on storage.objects;
create policy "suffah_photo_update" on storage.objects for update to authenticated
using (bucket_id='student-photos' and private.has_role(array['owner','admin','clerk']))
with check (
  bucket_id='student-photos'
  and private.has_role(array['owner','admin','clerk'])
  and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$'
  and exists (select 1 from public.students s where s.id::text || '.webp'=name)
);
