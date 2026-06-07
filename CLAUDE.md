# ระบบตรวจข้อสอบอัตโนมัติ — โรงเรียนนายางกลักพิทยาคม

## ข้อมูลโปรเจกต์
- **ชื่อระบบ:** ระบบตรวจข้อสอบปรนัยอัตโนมัติ (Auto Exam Grader)
- **โรงเรียน:** โรงเรียนนายางกลักพิทยาคม (สพม.ชัยภูมิ)
- **เจ้าของระบบ:** นายอดิศักดิ์ วนาใส (ครูที่ปรึกษา ม.5/1)
- **แยกอิสระ** จากระบบดูแลช่วยเหลือนักเรียน (`Downloads/CLAUDE.md`) — คนละโปรเจกต์ คนละโฟลเดอร์
- **เป้าหมาย:** ครูพิมพ์กระดาษคำตอบ OMR → นักเรียนระบายตอบ → ครูถ่ายรูป → เบราว์เซอร์อ่านวงที่ระบายเอง (OMR) → ตรวจเทียบเฉลย → ออกคะแนนทันที

## แนวคิดหลัก (Concept)
- ข้อสอบปรนัย **4 ตัวเลือก: ก ข ค ง** สูงสุด **60 ข้อ**
- ครูกรอกเฉลยในเว็บ + พิมพ์กระดาษคำตอบ OMR (มีจุดดำ 4 มุม)
- **อ่านด้วย OMR ในเบราว์เซอร์ ไม่ใช้ AI ไม่เสียเงิน ไม่ต้องมี API key** (ผู้ใช้เลือกแนวทางนี้เพราะต้องการฟรี)
- ผลตรวจ **แก้ไขได้** ในตาราง (OMR ไม่แม่น 100% ครูตรวจทาน/แก้ก่อนบันทึก) → คะแนนคำนวณสด

## Stack / เทคโนโลยี
- **Frontend:** HTML + CSS + Vanilla JavaScript (ไฟล์เดียว ไม่ใช้ Framework ไม่ใช้ library ภายนอก)
- **Database:** Supabase (PostgreSQL) — **โปรเจกต์เดียวกับระบบดูแลนักเรียน** `nayangklak-school` (ref `ujajukwmxulayxxxxmpr`) ใช้ร่วมกัน แต่แยกตาราง `exam_*`
- **OMR engine:** เขียนเอง vanilla JS (grayscale → Otsu → connected components หา marker → homography ปรับเพอร์สเปกทีฟ → วัดความเข้มแต่ละวง)
- **Font:** Sarabun (Google Fonts)
- **Theme:** Navy + Gold (พื้นหลังฟ้าอ่อน)

## Supabase (ใช้ร่วมกับระบบดูแลนักเรียน)
```
URL: https://ujajukwmxulayxxxxmpr.supabase.co  (= โปรเจกต์ nayangklak-school)
ANON KEY: อยู่ใน exam_grader.html (ตัวเดียวกับระบบดูแลนักเรียน)
RLS: ปิด + grant anon + permissive policy (ตาราง exam_*)
```

## โครงสร้างไฟล์
```
ตรวจข้อสอบ/
├── exam_grader.html                    ← เว็บหลัก 3 แท็บ + OMR engine (CSS + JS ในไฟล์เดียว)
├── exam_schema.sql                     ← SQL สร้างตาราง (รันใน Supabase SQL Editor แล้ว)
├── supabase/functions/grade-exam/
│   └── index.ts                        ← Edge Function proxy (Claude) — ❌ ไม่ใช้แล้ว เก็บไว้เผื่ออนาคต
├── answer_sheet_60q.pdf                ← กระดาษคำตอบเก่า (เลิกใช้ ใช้ตัวพิมพ์ OMR ในเว็บแทน)
└── CLAUDE.md                           ← ไฟล์นี้
```

## ⚠️ ประวัติการตัดสินใจสำคัญ
- เริ่มจากใช้ **Claude API (vision)** ตรวจ → แต่เป็นบริการจ่ายเงิน ผู้ใช้ไม่ต้องการ
- ทางเลือกที่เสนอ: Gemini ฟรีทีเออร์ / OMR เอง / Claude — **ผู้ใช้เลือก OMR อ่านเองในเครื่อง** (ฟรีถาวร ไม่ต้องมี key)
- ดังนั้น edge function `grade-exam` + Anthropic จึง**ไม่ถูกเรียกใช้แล้ว** (แท็บตรวจรัน OMR ใน client ล้วน)

## ตารางฐานข้อมูล (exam_schema.sql)
| ตาราง | รายละเอียด |
|-------|-----------|
| `exam_subjects` | รายวิชา + เฉลย: subject_name, class_level, room, exam_title, school_name, num_questions, answer_key (jsonb), updated_at (auto trigger) |
| `exam_results` | ผลตรวจรายคน: subject_id, student_name, student_no, room, score, total, percent, answers (jsonb) |
- RLS ปิดทุกตาราง (ตามแนวทางโปรเจกต์)

## โครงสร้าง exam_grader.html (3 แท็บ)
- **แท็บ 1 — รายวิชา & เฉลย:** dropdown เลือกรายวิชาที่บันทึกไว้ / ฟอร์มชื่อวิชา-ชั้น-ห้อง-จำนวนข้อ-ชื่อข้อสอบ-โรงเรียน / ตารางกรอกเฉลย ก-ง / บันทึก-ลบ (CRUD ลง Supabase)
- **แท็บ 2 — พิมพ์กระดาษคำตอบ:** ปรับหัวกระดาษ → ตัวอย่างสด (render เป็น **SVG**) → `window.print()` (มี `@media print` ซ่อน UI เหลือแต่ `#print-area`) มี **จุดดำ 4 มุม (registration markers)** + ช่องกรอก ชื่อ/เลขที่/ห้อง + วงกลมเปล่า (ตัวอักษร ก-ง อยู่ซ้ายวง วงข้างในเปล่าเพื่อให้ OMR อ่านง่าย)
- **แท็บ 3 — ตรวจข้อสอบ:** เลือกรายวิชา / กรอกชื่อ-เลขที่-ห้อง / อัปโหลดรูป → ปุ่มตรวจ (**รัน OMR ใน client**) → คะแนน + ตารางรายข้อ **(dropdown แก้คำตอบได้ คำนวณคะแนนสด)** + ปุ่มบันทึกลง `exam_results`

### ฟังก์ชันสำคัญ (JS)
| ฟังก์ชัน | หน้าที่ |
|---------|--------|
| `switchTab(name)` | สลับแท็บ |
| `loadSubjects()` / `fillSubjectDropdowns()` | ดึงรายวิชาจาก Supabase → เติม dropdown ทั้ง 2 ที่ |
| `onSelectSubject()` / `newSubject()` | โหลดรายวิชาเข้าฟอร์ม / เคลียร์ฟอร์มสร้างใหม่ |
| `saveSubject()` / `deleteSubject()` | POST/PATCH / DELETE ลง `exam_subjects` |
| `buildKeyGrid()` `getAnswerKey()` `setAnswerKey()` `clearKey()` | จัดการตารางเฉลย |
| `omrLayout(numQ)` | **คำนวณพิกัด marker + วงทุกข้อ — ใช้ร่วมกันทั้งตอนพิมพ์และตอนอ่าน (ต้องตรงกันเสมอ)** |
| `buildSheetSVG()` `renderSheet()` `initPrintTab()` | สร้าง SVG กระดาษคำตอบ OMR สำหรับพิมพ์ |
| `handleFile()` | อ่านไฟล์ → แปลงเป็น JPEG ผ่าน canvas (รองรับ HEIC) + ย่อขนาด |
| **OMR:** `omrToGray()` `otsu()` `detectMarkers()` `solveHomography()` `applyH()` `sampleDarkness()` `runOMR()` | pipeline อ่านกระดาษคำตอบในเบราว์เซอร์ |
| `gradeExam()` | โหลดรูป → `runOMR()` → `showResult()` |
| `showResult()` `recomputeScore()` | แสดงตาราง **แก้ไขได้** / คำนวณคะแนนใหม่ทุกครั้งที่แก้ |
| `saveResult()` | บันทึกคะแนนลง `exam_results` |
| `esc()` | escape HTML กัน XSS ในชื่อวิชา |

### G (Global State)
`{ subjects[], current, gradeSubject, lastResult, imageBase64, imageType, curKey, curNumQ }`

### OMR pipeline (สรุปการทำงาน)
1. แปลงรูปเป็น grayscale (ย่อ max 1200px) → หา threshold ด้วย **Otsu**
2. หา **จุดดำ 4 มุม** ด้วย connected-components (flood fill) → กรอง blob สี่เหลี่ยมทึบขนาดเหมาะ → จับคู่กับมุมภาพ
3. คำนวณ **homography** (canonical → ภาพถ่าย) แก้ภาพเอียง/บิด
4. map พิกัดวงแต่ละข้อ (`omrLayout`) ไปยังภาพ → วัด **ความสว่างเฉลี่ย** (`sampleMean`) ของแต่ละวง
5. ตัดสินแบบ **เทียบสัมพัทธ์ภายในข้อ** (สำคัญ — รองรับดินสอจาง): `paper` = วงสว่างสุด, `c0` = paper−วงเข้มสุด
   - `c0 < 22` → ไม่ตอบ `-` · วงเข้มรอง `c1 > 0.6·c0` → ไม่ชัด `?` · ไม่งั้น = วงเข้มสุด
- **เหตุผลที่ใช้ค่าสัมพัทธ์:** วิธีเดิม (วัด % พิกเซลที่ดำกว่า Otsu threshold) อ่านดินสอเทาจางไม่ออก เพราะ threshold ถูกดึงต่ำด้วย marker/ตัวอักษรสีดำ → ดินสอไม่ผ่านเกณฑ์
- **พารามิเตอร์ปรับได้:** maxDim(1200), sampleR(0.55×R), เกณฑ์ตัดสิน c0(22) / c1(0.6·c0, 18)
- **ทดสอบแล้ว:** ดำสนิท/ดินสอเทา 150–180 + เอียง + แสงเหลื่อม + ระบาย2วง = อ่านถูก 100% ทุกกรณี

## หมายเหตุการคิดคะแนน
- เปอร์เซ็นต์ = ข้อถูก / จำนวนข้อที่มีเฉลย (`Object.keys(key).length`) ไม่ใช่ numQ ทั้งหมด
- ผลจาก OMR แก้ไขได้ในตาราง → คะแนนคิดจากค่าใน dropdown (ไม่ใช่ค่าดิบจาก OMR) ผ่าน `recomputeScore()`

## ✅ สถานะใช้งานจริง
- ฐานข้อมูลใช้ได้แล้ว (รัน SQL + ปิด RLS + grant + policy เรียบร้อย)
- ตรวจด้วย OMR ทำงานได้ **ทันที ไม่ต้อง deploy/ตั้งค่าอะไรเพิ่ม** (ไม่พึ่ง server/AI)

## สิ่งที่ยังไม่มี (Roadmap)
- [x] เลือก/บันทึกรายวิชา + เฉลย (Supabase)
- [x] พิมพ์กระดาษคำตอบ OMR ปรับแต่งหัวกระดาษได้
- [x] ตรวจด้วย OMR ในเบราว์เซอร์ (ฟรี) + แก้ไขผลได้
- [x] กรอกข้อมูลนักเรียน + บันทึกคะแนนลง `exam_results`
- [ ] ตรวจหลายแผ่น/หลายคนต่อเนื่อง (batch)
- [ ] หน้าดูคะแนนย้อนหลัง / สรุปรายห้อง / export
- [ ] ออกรายงาน PDF ภาษาไทย (html2canvas)
- [ ] เชื่อมนักเรียนจากตาราง `students` ของระบบดูแลนักเรียน (เลือกชื่อแทนพิมพ์)
- [ ] (ถ้าอยากแม่นขึ้นกับลายมือ/เงา) ปรับ threshold หรือเพิ่ม adaptive threshold

## กฎการแก้ไขโค้ด (สำคัญ)
1. **Single HTML file** — CSS + JS อยู่ในไฟล์เดียวเสมอ (ต่อยอดจากเดิม ห้ามเขียนใหม่ทั้งหมด)
2. **ไม่ใช้ Framework / ไม่ใช้ library ภายนอก** — Vanilla JS ล้วน (รองรับ Safari iOS, OMR ก็เขียนเอง ไม่ใช้ OpenCV)
3. **Mobile first** — ครูถ่ายรูปจากมือถือเป็นหลัก ต้องใช้บน iPhone Safari ได้
4. **Font: Sarabun** ทุก element
5. **Theme สี:** navy `#1a2744`, navy-light `#243460`, gold `#c9a84c`, gold-light `#f0d080`, correct `#2e7d32`, wrong `#c62828`
6. **OMR: print กับ read ต้องใช้ `omrLayout()` ตัวเดียวกัน** — ถ้าแก้พิกัดวง/marker ต้องแก้ที่เดียวเสมอ ไม่งั้นอ่านเพี้ยน
7. **กระดาษคำตอบ render เป็น SVG** (คมตอนพิมพ์ + พิกัดตรงกับ OMR)
