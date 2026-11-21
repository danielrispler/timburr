-- Treadmill data Daniel types after a treadmill run. calories (006) and incline_pct (001) already exist; this adds steps and bounds incline.

alter table public.cardio
  add column steps int check (steps >= 0); -- what the treadmill showed, never measured by the phone

-- Not valid: rows written before this migration are not checked, but every later insert and update is.
alter table public.cardio
  add constraint cardio_incline_pct_range check (incline_pct between 0 and 40) not valid;
