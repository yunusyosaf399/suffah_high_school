# Global search — Suffah High School

Status: **dashboard entry and scope-selection preview implemented; real results deliberately deferred**.

The school owner requested one global search that can eventually retrieve school records across modules. Its initial location is the owner dashboard, and it must be convenient on Android, iOS, tablets and desktop.

## Searchable areas (future implementation)

- Students: admission numbers, names, classes/sections, parent/guardian contact.
- Staff and classes: staff names, subjects, assignments, grade/section.
- Attendance: attendance reports and student/date lookups (not one search-index write per daily mark).
- Finance: fees, invoices, receipt numbers, outstanding balances and fee reports.
- Academics: examination results, marks reports, academic report titles.
- Documents: indexed names, tags, linked student and document type.
- Pictures: student photos and other authorized image records by associated student/metadata, not pixel recognition.
- Notices and messages: authorized text and document titles.

## UX requirements

1. Prominent single search entry on the owner dashboard; one tap opens global search.
2. Compact, uncluttered screen with one input, optional scope chips, meaningful empty/loading/error states.
3. Query across approved modules only; show grouped results, module icon, record title, short metadata and a deep link.
4. Filters for class, academic year, dates, record type and status as relevant.
5. Text and keyboard controls responsive on phones, tablets and desktop; convenient touch targets even with 11–14sp body text.
6. Never show fake results. Until search indexes and module screens exist, display **Preview / Coming later**.

## Data and privacy design

- Honor the **same access permissions as the target record**. Parents can only find records for their linked children, and staff only records for their assigned responsibilities.
- Prefer a small denormalized `search_index` of eligible metadata or targeted indexed queries. Avoid full-collection scans and downloading every student record on each keystroke.
- Normalize case, spaces and identifiers; support partial names/IDs with bounded prefixes. Index Urdu/English naming thoughtfully when internationalization is enabled.
- Debounce typing, paginate (e.g. 20 results/page), cap response size, and cancel stale requests.
- Store stable `kind`, `recordId`, `title`, `subtitle`, `searchTokens` or normalized prefixes, `classId`, `academicYearId`, and permission metadata. Adjust per source.
- Upload neither sensitive document contents nor raw images into the search index. Search only approved filenames, labels, metadata and source links.
- If documents remain encrypted and stored only on a chosen desktop folder, cloud/mobile search **cannot** inspect their contents. A future local desktop index can search those files; cross-device metadata requires an explicit privacy decision.
- Keep Firestore read/write usage small, especially during daily attendance. Update the search index on stable record changes, not every high-frequency transactional event.
- Test consistency after record edits, archive, role changes, and parent–student link changes. Check for stale results after revocation.

## Delivery placement

Build live search **after** the underlying modules, record identifiers, and access policies are stable. The dashboard entry and visual scope selector are already present; backend indexing and actual results are not complete. Do not mark this feature production-ready until it passes cross-module and access-control tests.
