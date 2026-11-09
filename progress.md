# NSL Media Player — Progress

บันทึกสิ่งที่ทำไปแล้ว (อ้างอิงแผนใน `Plan.md`)

## สถานะล่าสุด — 2026-11-09

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
- `pubspec.yaml` ระบุ `sdk: ^3.13.7` เครื่องที่ใช้ตรวจโค้ดในเซสชันนี้มี Dart 3.13.5 จึงรัน `flutter analyze` ใน `lib/` ไม่ได้โดยตรง ต้องอัปเดต Flutter หรือใช้สำเนาที่ลดข้อกำหนด
- หลังเปลี่ยน plugin ต้องรัน `flutter pub get` แล้ว `flutter run -d windows` ใหม่ (hot restart ไม่พอ)

## ขั้นถัดไป (เสนอ)
1. ทดสอบ mini player, file picker, drag & drop บนเครื่องจริง และแก้ `SeekRow` ถ้าซ้อนกัน
2. **Milestone 3** — installer (Inno Setup) + registry เพื่อให้เป็น Default app ได้ (ตอนนี้การ์ด Default player จะแสดง 0 ไฟล์จนกว่าจะมี installer)
3. **Milestone 4** — สแกนโฟลเดอร์ library, อ่าน metadata/ปกอัลบั้ม, ค้นหาและจัดเรียง
4. **Milestone 5** — ซับไตเติล, SMTC/media keys, ตั้งปุ่มลัดเองได้, หมวดที่ตัดออกจาก Settings (ภาษา, click-through, โฟลเดอร์ Library)
