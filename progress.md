# NSL Media Player — Progress

Last updated: 2026-11-12
Overall status: Phase 1-5 done, Phase 7 ทำเฉพาะ acrylic, next Phase 8 (Phase 6 พักไว้ รอผู้ใช้เรียก)

บันทึกสิ่งที่ทำไปแล้ว (อ้างอิงแผนใน `Plan.md`)

## Features (ที่ยังเหลือจาก Plan.md)
| Feature | Priority | Phase |
|---|---|---|
| แสดงปกอัลบั้มในหน้าเล่นเพลง (แทนวงกลมสี) | Should | 1 |
| Media keys + SMTC | Should | 2 |
| หน้าตั้งปุ่มลัด + Reset to defaults | Should | 3 |
| กล่องลอยตั้งค่าด่วนในหน้าเล่น | Should | 4 |
| Sleep timer | Should | 5 |
| Upscale วิดีโอด้วย GLSL shader | Nice-to-have | 6 (พักไว้ — ไม่ทำจนกว่าผู้ใช้เรียก) |
| Acrylic/Mica, click-through, audio-only ตอนหน้าต่างถูกบัง, ภาษา | Nice-to-have | 7 |
| ทดสอบบนเครื่องจริง (Default app, Library, Home, mini ฯลฯ) | Must | 8 |

## Phases
### Phase 1: ปกอัลบั้มในหน้าเล่นเพลง — [x] done (2026-11-12)
- [x] ให้ `MusicView` รับ `ThumbnailService` และแสดงปกของไฟล์ที่เล่นอยู่ (fallback เป็นวงกลมสีเดิม ผ่าน `PathThumb.fallbackBuilder`)
- [x] ไฟล์วิดีโอที่เป็น audio-only ยังใช้การ์ด Audio only เดิม
- [x] `flutter analyze` (เหลือแค่ info เดิม ไม่มี error/warning) + `flutter test` ผ่าน 120 ข้อ
- ยังไม่ได้ดูหน้าตาบนเครื่องจริง (ปกขึ้นไหม, มุมโค้ง/ขนาดพอดีไหม) — ไปอยู่ใน Phase 8

### Phase 2: Media keys + SMTC — [x] done (2026-11-12) ยกเว้นปก/ศิลปิน
- [x] เพิ่ม `smtc_windows ^1.1.0` (ต้องมี Rust: ติดตั้ง `Rustlang.Rustup` แล้ว), `lib/services/smtc_service.dart` ส่งชื่อ/สถานะ/ตำแหน่ง รับปุ่ม play/pause/next/prev
- [x] สวิตช์ "Windows media controls" ใน Settings > Playback (ปิด = ปิด SMTC)
- [x] `flutter analyze` ไม่มี error/warning, `flutter build windows --release` ผ่าน (มี `smtc_windows.dll`), เปิด exe ได้
- ข้อจำกัด v1: ยังไม่ส่งปกอัลบั้ม/ศิลปิน (controller ไม่มี tag), mini player แยกโปรเซสไม่มี SMTC (ตอนใช้ mini แผงของแอปหลักจะถูกปิดไว้)
- ยังไม่ได้ทดสอบกดปุ่ม media key จริง / ดูแผงเสียงของ Windows — ไปอยู่ Phase 8

### Phase 3: ตั้งปุ่มลัดเอง — [x] done (2026-11-12)
- [x] `lib/services/shortcut_bindings.dart` (ShortcutAction/KeyCombo/ShortcutBindings เก็บเฉพาะที่แก้เป็น JSON ใน prefs key `shortcuts`), `lib/ui/shortcut_editor.dart` (dialog เพิ่ม/ลบปุ่มโดยกดปุ่มจริง, ชนกับ action อื่นจะถามก่อนย้าย, Reset to default ต่อ action)
- [x] Settings > Shortcuts: ปุ่มดินสอต่อแถว + "Reset all to defaults"; `player_page.dart` สร้าง Shortcuts จาก settings และรีบิลด์เมื่อแก้
- [x] ตัวกัน "พิมพ์ในช่องค้นหา" ใช้ได้กับปุ่มที่ตั้งเอง (plain = ไม่มี Ctrl/Alt)
- [x] unit test 5 ข้อ (`test/shortcut_bindings_test.dart`) รวม 125 ข้อผ่าน, analyze ไม่มี error/warning, build release + เปิดแอปผ่าน
- ข้อจำกัด: mini player (โปรเซสแยก) อ่านปุ่มตอนเปิดครั้งต่อไป; ยังไม่ได้ลองกดตั้งปุ่มบนหน้าจอจริง → Phase 8

### Phase 4: กล่องลอยตั้งค่าด่วนในหน้าเล่น — [x] done (2026-11-12)
- [x] `lib/ui/quick_settings.dart`: ปุ่ม tune (Quick settings) ในแถบควบคุม เปิดกล่องลอยปรับ ความเร็ว / คุณภาพวิดีโอ (เฉพาะตอนมีภาพ) / แทร็กเสียง (ถ้ามี >1) / ซับไตเติล + Load file…; ไอคอนสว่างเมื่อความเร็วไม่ใช่ 1× หรือเปิดซับ
- [x] แทนปุ่มความเร็ว, ปุ่ม Quality และ `TracksButton` เดิมในแถบควบคุม (ลบ `TracksButton` แล้ว) — ไม่ใส่ตัวเลือก upscale ตามที่ตกลง (Phase 6 พักไว้)
- [x] analyze ไม่มี error/warning, test 125 ผ่าน, build release + เปิดแอปผ่าน
- ใช้ `PopupMenuButton` ที่มีรายการเดียวเป็นแผงของเราเอง (ปิดเมื่อคลิกนอกกล่อง) ยังไม่ได้ลองกดจริง → Phase 8 (โดยเฉพาะ: กด chip แล้วกล่องไม่ปิดเองและอัปเดตค่า)

### Phase 5: Sleep timer — [x] done (2026-11-12)
- [x] `lib/services/sleep_timer.dart` (ตรรกะล้วน ทดสอบได้) + `sleep_port.dart` (ต่อกับ controller): นับถอยหลัง 15/30/45/60/90 / กำหนดนาทีเอง / ตั้งเวลานาฬิกา (ถ้าผ่านแล้วถือเป็นพรุ่งนี้) / หยุดเมื่อจบไฟล์; ใช้ `DateTime` เป้าหมายเทียบนาฬิกา ไม่เพี้ยนตอนเครื่อง sleep
- [x] fade out ก่อน pause แล้วคืนระดับเสียง (ตั้งได้ที่ Settings > Playback > Sleep timer fade-out: Off/5/10/30 วิ, ค่าเริ่มต้น 10); ยกเลิกระหว่าง fade ก็คืนเสียง; ไม่ปิดแอป
- [x] UI: ส่วน "Sleep timer" ใน Quick settings แสดงเวลาที่เหลือ + Cancel, ไอคอน tune สว่างเมื่อมีตัวจับเวลา
- [x] ใช้ได้ตอน mini player แยกโปรเซสเปิดอยู่: ตัวจับเวลาอยู่ที่แอปหลัก สั่ง pause ไปที่ mini ผ่าน IPC (`{cmd: pause}` ใหม่); ข้อจำกัด: ไม่ fade และโหมด "จบไฟล์" รอไม่ได้ (ไม่รู้เวลาที่เหลือ) ใน mini
- [x] unit test 7 ข้อ (`test/sleep_timer_test.dart`) รวม 132 ข้อผ่าน, analyze ไม่มี error/warning, build release + เปิดแอปผ่าน
- ยังไม่ได้ลองกดจริง/ฟังเสียง fade และทดสอบ mini จริง → Phase 8

### Phase 6: Upscale GLSL — [ ] พักไว้ (ON HOLD) ห้ามเริ่มจนกว่าผู้ใช้เรียก
- [ ] ทดลอง shader กับ media_kit, Settings Off/Fast/Quality, แพ็ก .glsl, ปิดเมื่อ `reducedLoad`

### Phase 7: ของเสริม/ขัดเกลา — [~] ทำเฉพาะข้อที่ผู้ใช้เลือก (2026-11-12)
- [x] พื้นหลังโปร่งแบบเบลอของ mini player ด้วย `flutter_acrylic ^1.1.4`: Settings > Mini player > Blurred background (ปิดเป็นค่าเริ่มต้น); เปิดแล้วใช้ `WindowEffect.acrylic` สี tint = สีพื้นหลังธีม alpha ตามสไลเดอร์ Opacity (หน้าต่างไม่ใช้ setOpacity ตอนเบลอ ตัวหนังสือจึงไม่จาง), การ์ดเสียงไม่วาดพื้นหลังเอง; ถ้าเบลอไม่ได้จะ fallback เป็นโปร่งแบบเดิมอัตโนมัติ
  - วิดีโอ (PiP) เต็มหน้าต่างด้วยภาพ จึงไม่เห็นผลเบลอ
  - analyze ไม่มี error/warning, test 132 ผ่าน, build release + เปิดแอปผ่าน แต่ **ยังไม่เคยเห็นผลเบลอจริง** (ต้องเปิด mini แล้วดูด้วยตา: เบลอขึ้นไหม, ขอบ/มุมโค้งถูกไหม, ลากหน้าต่างหน่วงไหม, สลับกลับหน้าต่างหลักแล้วเบลอหายไหม) → Phase 8
- [ ] ข้ออื่น (click-through, audio-only ตอนหน้าต่างถูกบัง, ภาษา, ปรับแต่ง UI) — ผู้ใช้เลือกไม่ทำตอนนี้
### Phase 8: ทดสอบบนเครื่องจริง (ดูรายการ "ยังไม่ได้ยืนยัน") — [ ] not started

## Notes / Decisions / Blockers
- 2026-11-12: progress.md เดิมไม่มีโครงเฟส จัดรูปแบบใหม่ตาม nsl-dev โดยเก็บบันทึกเดิมไว้ด้านล่าง; Plan.md ติ๊กไปไกลกว่า progress.md เดิม (Thumbnail/Grid/Playlists/Home แท็บ/History/mini process ทำแล้ว) ถือตาม Plan.md และโค้ด
- 2026-11-12: Plan.md (f4f0e27) เพิ่ม upscale GLSL / quick settings / sleep timer ผู้ใช้สั่งให้ upscale อยู่ในแผนแต่ **ไม่ทำจนกว่าผู้ใช้จะเรียก** (Phase 6 ON HOLD ข้ามไปเฟสถัดไปได้)

## สถานะล่าสุด — 2026-11-11

### ทำเสร็จ (เซสชันนี้)
- **Installer (Milestone 3)**: `installer/nsl_media_player.iss` ติดตั้งแบบ per-user เขียน HKCU (ProgID, Applications, Capabilities, RegisteredApplications, `OpenWithProgids` 11 นามสกุล) ไม่แย่ง default ของแอปอื่น การ์ด Default player ใน Settings นับจาก `OpenWithProgids`
- **Video quality Auto**: ลดเหลือ 480p เมื่อย่อหน้าต่าง/เข้า mini player (`reducedLoad` ใน controller) ค่า quality จำไว้อยู่แล้ว
- **Audio only by default**: สวิตช์ใน Settings > Video
- **ซับไตเติล + เลือกแทร็กเสียง/ซับ**: `TracksButton` ใน `controls.dart` โหลดไฟล์ .srt/.ass/.vtt ได้
- **Mini player**: เพิ่มความสูงหน้าต่าง 232 → 248 กันแถบ seek ซ้อน Opacity
- `flutter analyze` รันได้แล้ว: ไม่มี error/warning เหลือแค่ info เรื่อง `windowManager` deprecated (legacy API)
- `flutter build windows --release` ผ่าน และเปิด exe ได้ไม่ค้าง (ตรวจแค่ว่าหน้าต่างขึ้น ไม่ได้กดทดสอบฟีเจอร์)

- **Library (Milestone 4)**: `lib/services/library_service.dart` + `lib/ui/library_view.dart` เพิ่มโฟลเดอร์ → สแกน (เฉพาะไฟล์ใหม่/ที่แก้ไขจะอ่าน tag ใหม่) → ค้นหา/กรอง/เรียง/ปกอัลบั้ม กดแถวเพื่อเล่นทั้งรายการที่กรองอยู่ มี unit test 6 ข้อ (`test/library_service_test.dart`)
- **แก้บั๊ก `fileNameOf`**: regex `[\/]` ไม่ตัด `\` ของ Windows ทำให้ชื่อในคิว/ประวัติเป็น path เต็ม (เจอจากเทสต์) แก้เป็น `[\\/]`
- Installer คอมไพล์ผ่านแล้ว (`installer\Output\NSL-Media-Player-Setup.exe`) แต่ยังไม่ได้ติดตั้งทดสอบ

### ข้อจำกัดของ Library ที่รู้
- อ่าน tag แบบ synchronous บน UI isolate (แบ่ง yield ทุก 20 ไฟล์) ไลบรารีใหญ่หลักพันไฟล์อาจกระตุกตอนสแกนครั้งแรก ถ้าเจอให้ย้ายไป isolate
- ไฟล์วิดีโอแสดงด้วยชื่อไฟล์ ไม่อ่าน tag/ไม่มี thumbnail

### ยังไม่ได้ยืนยันบนเครื่องจริง (ต้องกดทดสอบเอง)
- หน้า Library: เพิ่มโฟลเดอร์จริง, ปกขึ้นไหม, ค้นหา/เรียง, กดเล่นแล้วเด้งไปหน้าเล่น
- Mini player หลังเพิ่มความสูง: แถบ seek ยังซ้อนกับ Opacity หรือไม่
- Open file / Open folder / ลากไฟล์วาง (file_picker 6.2.1)
- Hardware decoding และ "เล่นต่ออัตโนมัติ"
- Quality Auto และ Audio only by default
- ซับไตเติล: ซับขึ้นบนวิดีโอจริงไหม, สลับแทร็กเสียง
- Installer: ยังไม่ได้คอมไพล์ (ต้องติดตั้ง Inno Setup) และยังไม่ได้ทดสอบดับเบิลคลิกไฟล์

### ค้างอยู่
- Audio-only ตอนหน้าต่างถูกบัง (ไม่มี event ใน window_manager ต้องใช้ native hook)
- Milestone 4 ทั้งหมด, SMTC/media keys, ตั้งปุ่มลัดเอง

---

## สถานะก่อนหน้า — 2026-11-09

### ทำเสร็จ
- **ซิงก์ Plan.md กับโค้ด**: ติ๊ก 40 รายการที่มีโค้ดอยู่แล้ว (queue, Mixed Playlist, Audio-only, Video quality, mini player, ธีม, Home) และระบุรายการที่ยังไม่ทำ
- **หน้า Settings เต็มรูปแบบ** (`lib/ui/settings_page.dart`) แทน dialog เดิม
  - 7 หมวด: General, Playback, Video, Mini player, Library, Shortcuts, About
  - ตั้งค่าที่ใช้งานได้จริง: theme/accent, จำขนาดหน้าต่าง, resume, เล่นต่ออัตโนมัติ, ความดัง/ความเร็วเริ่มต้น, ระยะ seek, คุณภาพวิดีโอ, hardware decoding, Audio-only ตอนย่อหน้าต่าง, ความโปร่งใส/always-on-top/ตำแหน่ง mini player, เก็บ/ล้างประวัติ
  - การ์ด Default player: ปุ่มเปิด `ms-settings:defaultapps` และแสดงจำนวนนามสกุลที่ลงทะเบียน
  - เพิ่มปุ่มลัด `A` สลับ Audio-only
- **Home + Dashboard**: ตรวจแล้วว่ามีอยู่ใน `home_page.dart` ตรงกับบอร์ดดีไซน์ ปุ่ม Settings เปิดหน้าใหม่

### บั๊กที่แก้
| อาการ | สาเหตุ | วิธีแก้ |
|---|---|---|
| จอขาวตอนเปิดแอป | เรียก native ของ mpv แบบ `await` ก่อน `runApp` | `runApp` ก่อน แล้วค่อยตั้งค่าเครื่องเล่นพร้อม try/catch (`_applyPlayerSettings` ใน `main.dart`) |
| Build ไม่ผ่าน (`String starting with '`) | `\n` ใน log ถูกเขียนเป็นขึ้นบรรทัดใหม่จริง | แก้ string ใน `main.dart` |
| Open file ขึ้น `MissingPluginException` | `file_picker ^3.0.4` ไม่มีโค้ด Windows | เปลี่ยนเป็น `^6.2.1` (รุ่น 7+ ขัดกับ `desktop_drop` ที่ใช้ `cross_file` คนละรุ่น) |
| Mini player จัดวางผิดจนต้องลากปรับขนาด | `setResizable(false)` ก่อน `setSize` ทำให้ Windows ไม่เปลี่ยนขนาด | ตั้งขนาดตอนยัง resizable แล้วค่อยล็อก (`_enterMini` ใน `player_page.dart`) |

### ยังไม่ได้ยืนยันบนเครื่องจริง
- แก้ mini player แล้วแต่ยังไม่ได้ทดสอบ: ในภาพหน้าจอแถบ seek กับแถบ Opacity ซ้อนกัน อาจเป็นปัญหาแยกใน `SeekRow` (`lib/ui/controls.dart`)
- Open file / Open folder / ลากไฟล์วาง หลังเปลี่ยน `file_picker`
- การเปลี่ยนค่า hardware decoding และ "เล่นต่ออัตโนมัติ" (ใช้ mpv `keep-open`) ว่าทำงานตามที่ตั้ง

### หมายเหตุสภาพแวดล้อม
- (แก้แล้ว 2026-11-11) `flutter analyze` และ `flutter build windows` รันได้ปกติบนเครื่องนี้
- หลังเปลี่ยน plugin ต้องรัน `flutter pub get` แล้ว `flutter run -d windows` ใหม่ (hot restart ไม่พอ)

## ขั้นถัดไป (เสนอ)
1. ทดสอบ mini player, file picker, drag & drop บนเครื่องจริง และแก้ `SeekRow` ถ้าซ้อนกัน
2. **Milestone 3** — installer (Inno Setup) + registry เพื่อให้เป็น Default app ได้ (ตอนนี้การ์ด Default player จะแสดง 0 ไฟล์จนกว่าจะมี installer)
3. **Milestone 4** — สแกนโฟลเดอร์ library, อ่าน metadata/ปกอัลบั้ม, ค้นหาและจัดเรียง
4. **Milestone 5** — ซับไตเติล, SMTC/media keys, ตั้งปุ่มลัดเองได้, หมวดที่ตัดออกจาก Settings (ภาษา, click-through, โฟลเดอร์ Library)
