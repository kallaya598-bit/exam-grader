-- ============================================================
-- ระบบตรวจข้อสอบอัตโนมัติ — โครงสร้างฐานข้อมูล
-- รันใน Supabase SQL Editor (โปรเจกต์เดียวกับระบบดูแลนักเรียน)
-- โปรเจกต์: https://ujajukwmxulayxxxxmpr.supabase.co
-- ============================================================

-- ----------------------------------------------------------------
-- ตาราง exam_subjects : รายวิชา + เฉลย (1 แถว = 1 ชุดข้อสอบที่บันทึกไว้)
-- ----------------------------------------------------------------
create table if not exists exam_subjects (
  id            bigint generated always as identity primary key,
  subject_name  text not null,                              -- ชื่อรายวิชา เช่น ฟิสิกส์
  class_level   text,                                       -- ชั้น เช่น ม.5
  room          text,                                       -- ห้อง เช่น 5/1
  exam_title    text,                                       -- ชื่อข้อสอบ เช่น สอบกลางภาค 1/2569
  school_name   text default 'โรงเรียนนายางกลักพิทยาคม',
  num_questions int  not null default 20,
  choices       int  not null default 4,                    -- จำนวนตัวเลือก (เลือกได้ 4 = ก-ง หรือ 5 = ก-จ)
  answer_key    jsonb not null default '{}'::jsonb,         -- เฉลย {"1":"ก","2":"จ",...}
  question_scores jsonb not null default '{}'::jsonb,       -- คะแนนรายข้อ {"1":1,"2":2.5,...}
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

alter table exam_subjects disable row level security;
create index if not exists idx_exam_subjects_name on exam_subjects(subject_name);

-- อัปเดต updated_at อัตโนมัติเมื่อมีการแก้ไข
create or replace function set_exam_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_exam_subjects_updated on exam_subjects;
create trigger trg_exam_subjects_updated
  before update on exam_subjects
  for each row execute function set_exam_updated_at();

-- ----------------------------------------------------------------
-- ตาราง exam_results : ผลการตรวจรายคน (ตัวเลือก — เก็บคะแนนไว้ดูย้อนหลัง)
-- ----------------------------------------------------------------
create table if not exists exam_results (
  id            bigint generated always as identity primary key,
  subject_id    bigint references exam_subjects(id) on delete cascade,
  student_name  text,
  student_no    text,
  room          text,
  score         numeric,
  total         numeric,
  percent       numeric,
  answers       jsonb,                                       -- คำตอบนักเรียนที่ AI อ่านได้
  graded_at     timestamptz default now()
);

alter table exam_results disable row level security;
create index if not exists idx_exam_results_subject on exam_results(subject_id);

-- อัปเกรดฐานข้อมูลเดิมให้รองรับคะแนนรายข้อและคะแนนทศนิยม
alter table exam_subjects
  add column if not exists question_scores jsonb not null default '{}'::jsonb;
alter table exam_results alter column score type numeric using score::numeric;
alter table exam_results alter column total type numeric using total::numeric;

-- ============================================================
-- เสร็จแล้ว ✅  ระบบพร้อมเก็บรายวิชา/เฉลย/คะแนน
-- ============================================================
