# NSL Media Player — Progress

บันทึกสิ่งที่ทำไปแล้ว (อ้างอิงแผนใน `Plan.md`)

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
