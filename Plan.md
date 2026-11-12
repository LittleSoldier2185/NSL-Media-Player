# NSL Media Player — Plan

## 1. ภาพรวม
โปรแกรมเล่นไฟล์เสียงและวิดีโอสำหรับ **Windows (PC)** สร้างด้วย **Flutter Desktop**
เป้าหมายหลัก: เล่นได้ทั้งเสียงและวิดีโอในแอปเดียว และตั้งเป็นแอปเริ่มต้น (default) สำหรับเปิดไฟล์มีเดียได้

## 2. ขอบเขต
**อยู่ในแผน**
- เล่นไฟล์เสียงและวิดีโอ
- รองรับลากไฟล์มาวาง และเปิดผ่าน "Open with" ของ Windows
- ลงทะเบียนเป็นตัวเลือก Default app ผ่าน installer

**ยังไม่ทำ (ภายหลัง)**
- Android / มือถือ
- เขียน decoder เอง (ใช้ libmpv ผ่าน media_kit แทน)
- Equalizer, visualizer, cast, streaming หลายโปรโตคอล

## 3. Tech Stack
| ส่วน | Package / เครื่องมือ |
|---|---|
| ตัวเล่นหลัก | `media_kit`, `media_kit_video`, `media_kit_libs_windows_video` |
| เลือกไฟล์/โฟลเดอร์ | `file_picker` |
| ลากไฟล์มาวาง | `desktop_drop` |
| จัดการหน้าต่าง (fullscreen, opacity ฯลฯ) | `window_manager` |
| เอฟเฟกต์โปร่งแสง (ทางเลือก) | `flutter_acrylic` |
| เก็บ playlist / ตำแหน่งที่ดูค้าง | `shared_preferences` หรือ `drift` (SQLite) |
| อ่าน metadata / ปกอัลบั้ม | `audio_metadata_reader` หรือ `metadata_god` |
| Media keys + SMTC ของ Windows | `smtc_windows` |
| เปิดหน้า Default apps | `url_launcher` (`ms-settings:defaultapps`) |
| Installer | Inno Setup (แนะนำ) หรือ MSIX |

## 4. โครงสร้างโปรเจกต์ (เสนอ)
```
lib/
  main.dart            // รับ args จาก command line
  player_controller/   // logic ควบคุมการเล่น (play, seek, queue)
  services/            // file association, settings, metadata, SMTC
  ui/                  // หน้าจอ: โหมดเพลง / โหมดวิดีโอ / playlist
installer/
  nsl_media_player.iss // สคริปต์ Inno Setup
```

## 5. Roadmap

### Milestone 1 — MVP เล่นไฟล์เดียว
- [x] สร้างโปรเจกต์ Flutter Windows ชื่อ NSL Media Player
- [x] เล่นไฟล์เสียง/วิดีโอด้วย media_kit
- [x] Controls: play/pause, seek bar, volume, mute, ความเร็วการเล่น
- [x] ลากไฟล์มาวาง + รับ path จาก `main(List<String> args)`
- [x] ปุ่มลัดคีย์บอร์ด + fullscreen

### Milestone 2 — Playlist และคิวเล่น
- [x] Playlist / คิว: ถัดไป, ก่อนหน้า, สุ่ม, วนซ้ำ
- [x] เพิ่มหลายไฟล์ / ทั้งโฟลเดอร์เข้าคิว
- [x] **โหมด Mixed Playlist**: ผสมไฟล์วิดีโอกับเสียงใน playlist เดียวกันได้
  - [x] ตรวจชนิดไฟล์ (เสียง/วิดีโอ) จากนามสกุล หรือจากแทร็กวิดีโอของไฟล์
  - [x] สลับ UI อัตโนมัติระหว่างโหมดเพลง (โชว์ปกอัลบั้ม) กับโหมดวิดีโอเมื่อเปลี่ยนไฟล์
  - [x] ไอคอนบอกชนิดไฟล์ในรายการ + ตัวกรอง (ทั้งหมด / เสียง / วิดีโอ)
- [x] **โหมด Audio-only (ประหยัดทรัพยากร)**: เล่นไฟล์วิดีโอเฉพาะเสียง ไม่ decode ภาพ
  - [x] ปิดการ decode วิดีโอที่ตัวเล่น: ตั้ง property ของ mpv `vid=no` ผ่าน `NativePlayer.setProperty` (ลด CPU/GPU จริง ไม่ใช่แค่ซ่อนภาพ)
  - [x] ไม่สร้าง `Video` widget ในโหมดนี้ แสดงปก/หน้าจอเพลงแทน
  - [x] สลับเปิด/ปิดได้ระหว่างเล่น (ตั้ง `vid=auto` เพื่อกลับมาแสดงภาพที่ตำแหน่งเดิม)
  - [x] เปิดอัตโนมัติเมื่อหน้าต่างถูกย่อ (ตั้งค่าใน Settings > Video)
  - [x] ตั้งค่า Audio-only เป็นค่าเริ่มต้นทั้งแอป (Settings > Video > Audio only by default)
  - [ ] ตอนหน้าต่างถูกบัง (window_manager ไม่มี event occlusion ต้องหาวิธีอื่น เช่น native hook)
  - [x] ใช้ร่วมกับ Mini player ได้ (mini player + audio-only = เบาที่สุด)
- [x] **Video quality (ลดจากต้นฉบับได้ ขยายไม่ได้)**
  - [x] ความละเอียดของไฟล์ต้นฉบับเป็นเพดานสูงสุด ไม่มี upscale
  - [x] ตัวเลือก: Original / 1080p / 720p / 480p / 360p โดยแสดงเฉพาะค่าที่ต่ำกว่าหรือเท่ากับความสูงของไฟล์ (ไฟล์ 720p จะไม่มีตัวเลือก 1080p)
  - [x] ใช้ filter ของ mpv `vf=scale=-2:<ความสูง>` เปลี่ยนได้ระหว่างเล่น
  - [x] ปุ่ม Quality ในแถบควบคุมวิดีโอ + ค่าเริ่มต้นใน Settings
  - [x] จำค่าที่เลือก และตัวเลือก Auto (ลดเหลือ 480p อัตโนมัติเมื่อใช้ mini player หรือย่อหน้าต่าง)
  - หมายเหตุ: ไฟล์ในเครื่องยังถูก decode ที่ความละเอียดเดิม การลดคุณภาพช่วยลดภาระตอนวาดภาพ ถ้าต้องการประหยัดจริงให้ใช้โหมด Audio-only
- [x] บันทึก playlist ล่าสุด
- [x] จำขนาดหน้าต่างและระดับเสียง

### Milestone 3 — Default App (Windows)
- [x] ทำ installer ด้วย Inno Setup (`installer/nsl_media_player.iss` — เขียนแล้ว ยังไม่ได้คอมไพล์/ทดสอบ)
- [x] เขียน Registry ลง `HKCU` (ไม่ต้องใช้สิทธิ์ admin)
  - ProgID + คำสั่งเปิดไฟล์ `"...\nsl_media_player.exe" "%1"`
  - `OpenWithProgids` ของแต่ละนามสกุล
  - `Capabilities` + `RegisteredApplications` เพื่อให้ขึ้นใน Settings > Default apps
- [x] ปุ่ม "ตั้งเป็นแอปเริ่มต้น" ในแอป → เปิด `ms-settings:defaultapps`
- [ ] ทดสอบ: ดับเบิลคลิกไฟล์ → เปิดใน NSL Media Player

**นามสกุลที่รองรับ**
- เสียง: `.mp3 .flac .wav .m4a .ogg .aac`
- วิดีโอ: `.mp4 .mkv .avi .mov .webm`

> หมายเหตุ: Windows 10/11 ไม่อนุญาตให้โปรแกรมตั้งตัวเองเป็น default อัตโนมัติ ผู้ใช้ต้องเลือกเองในหน้า Default apps

### Milestone 4 — Library และ metadata
- [x] สแกนโฟลเดอร์ แยกเพลง / วิดีโอ (`LibraryService`, หน้า Library ใน Home, cache index ที่ `%APPDATA%\NSL Media Player\library.json`)
- [x] อ่านชื่อเพลง ศิลปิน อัลบั้ม และแสดงปก (`audio_metadata_reader`; ปกแสดงในรายการ Library แล้ว ยังไม่ขึ้นที่หน้าเล่นเพลง)
- [x] **Thumbnail ใน Library** (`ThumbnailService`): ปกอัลบั้มที่ฝังในไฟล์ (หรือ cover.jpg/folder.jpg ในโฟลเดอร์) สำหรับเพลง, เฟรมที่ 10% ของไฟล์สำหรับวิดีโอ (ดึงด้วย media_kit แบบไม่มีหน้าต่าง), cache บนดิสก์ที่ `%APPDATA%\NSL Media Player\thumbs` (PNG 256px) + memory, คิวทำทีละวิดีโอ/ข้ามแถวที่เลื่อนผ่าน, ปุ่ม Clear thumbnails ใน Settings > Library
- [x] **Grid view ใน Library**: สลับ List/Grid (จำค่าไว้), การ์ด 16:9 พร้อม badge ความยาว, เลือกหลายรายการ/เมนู ⋮ ใช้ได้ทั้งสองโหมด
  - [ ] ยังไม่ได้ทดสอบ UI บนเครื่องจริง (ทดสอบ logic ด้วย unit test และการดึงเฟรมวิดีโอจริงด้วยโปรแกรมทดลองแล้ว)
  - [x] Thumbnail แสดงที่การ์ด Continue (Home), รายการในเพลย์ลิสต์ และแผงคิวด้วย (ใช้แคชเดียวกับ Library)
- [x] ค้นหาและจัดเรียง library (ค้นหา title/artist/album, กรอง All/Music/Videos, เรียง Title/Artist/Album/Recently added)
- [x] **Playlists ที่ตั้งชื่อและบันทึกได้** (`PlaylistService`, `playlists_view.dart`) ไฟล์มาจากโฟลเดอร์ไหนก็ได้
  - [x] สร้าง/เปลี่ยนชื่อ/ลบ หลายเพลย์ลิสต์ (ชื่อไม่ซ้ำ), เก็บที่ `%APPDATA%\NSL Media Player\playlists.json`
  - [x] Library: เมนู ⋮ ต่อแถว (Add to queue / Add to playlist) + โหมด Select เลือกหลายแถวข้ามโฟลเดอร์
  - [x] หน้า Playlists: เล่นทั้งลิสต์/เริ่มจากเพลงที่กด, Add to queue, ลากเรียงลำดับ, ลบเพลงออก, ไฟล์ที่หายแสดงจางและข้ามตอนเล่น
  - [x] แผงคิว: ปุ่ม "Save as playlist" บันทึกคิวปัจจุบัน
  - [ ] ยังไม่ได้ทดสอบ UI บนเครื่องจริง (ทดสอบเฉพาะ logic ด้วย unit test และ build/เปิดแอปผ่าน)
- [ ] แสดงปกอัลบั้มในหน้าเล่นเพลง (music view) แทนวงกลมสี
- [x] บันทึกโฟลเดอร์เก็บสื่อได้หลายอัน: จัดการได้ทั้งในหน้า Library และ Settings > Library (เพิ่ม/ลบ/สแกนใหม่), กดชื่อโฟลเดอร์เพื่อกรองดูเฉพาะอันนั้น, กันโฟลเดอร์ซ้ำ/ซ้อนกัน
- [x] จำตำแหน่งที่ดูค้างไว้ (resume)
- [x] **หน้า Home + Dashboard** (ตามบอร์ด "Home + Dashboard" ในดีไซน์): หน้าแรกของแอปแสดงรายการล่าสุด / ดูต่อ / library

### Milestone 5 — ฟีเจอร์เสริมและขัดเกลา
- [x] ซับไตเติล + เลือกแทร็กเสียง/ซับ (ปุ่มเมนูในแถบควบคุม โหลดไฟล์ .srt/.ass/.vtt ได้ — เขียนแล้ว ยังไม่ได้ทดสอบกับไฟล์จริง)
- [ ] Media keys + SMTC (ชื่อเพลงในแผงควบคุมเสียงของ Windows)
- [x] โหมดเพลง (โชว์ปกอัลบั้ม) แยกจากโหมดวิดีโอ
- [x] Mini player (หน้าต่างเล็ก always-on-top)
  - [x] แสดงภาพวิดีโอใน mini player ได้ (Settings > Mini player > Show video, ค่าเริ่มต้นเปิด) สลับภาพ/เสียงอย่างเดียวได้
  - [x] **Mini player เปิดเป็นหน้าต่าง/โปรเซสแยก ตัวแอปหลักยังอยู่** (`mini_ipc.dart`): กด Mini → เปิด `nsl_media_player.exe --mini` ส่งคิว/ตำแหน่ง/ความดังให้ผ่าน socket ในเครื่อง (มี token), แอปหลักหยุดเล่นแต่ยังใช้เลือกเพลงได้ — เล่นจาก Library/Playlists/เปิดไฟล์ในแอปหลักจะส่งไปเล่นใน mini, ปุ่ม Bring back / ขยายใน mini ส่งตำแหน่งกลับ (ขยาย = เล่นต่อที่แอปหลัก, ปิด = หยุดไว้), ประวัติการดู/ขนาดหน้าต่างที่ปรับ ส่งกลับไปบันทึกที่แอปหลัก; ปิดสวิตช์ได้ที่ Settings > Mini player > Open in its own window (กลับไปแบบย่อหน้าต่างเดิม), ถ้าเปิด mini ไม่สำเร็จจะ fallback เป็นแบบย่อหน้าต่างเดิมอัตโนมัติ (ทดสอบ protocol ด้วย unit test + ทดสอบโปรเซส mini จริงกับแอปหลักจำลองแล้ว ยังไม่ได้ทดสอบแอปหลักจริงคู่กับ mini จริง)
  - [x] ปรับขนาดหน้าต่าง mini player ได้ด้วยการลากขอบ: วิดีโอล็อกสัดส่วนภาพ (กว้าง 220–1000, สูง 120–720), การ์ดเสียงปรับได้เฉพาะความกว้าง (340–720); จำขนาดที่ปรับไว้, ปุ่ม Reset size ใน Settings > Mini player (ยังไม่ได้ทดสอบบนเครื่องจริง โดยเฉพาะการล็อกสัดส่วนกับ event ปรับขนาดของ window_manager)
  - [x] วิดีโอใช้ดีไซน์แบบ Picture-in-Picture (เหมือน Chrome/Edge): ภาพเต็มหน้าต่าง, หน้าต่างปรับสัดส่วนตามวิดีโอ (แนวนอนกว้าง 420, แนวตั้งสูง 480), ปุ่มควบคุมโผล่ทับภาพตอนเมาส์ชี้หรือตอนหยุด (ปุ่ม pin / opacity / sound-only / ขยาย / ปิด + seek + prev/play/next), คลิกภาพ = เล่น/หยุด, ลากตรงไหนก็ย้ายหน้าต่าง, มีเส้น progress บางๆ ตอนซ่อนปุ่ม; ไฟล์เสียงยังใช้การ์ดเดิม (ยังไม่ได้ทดสอบหน้าตาบนเครื่องจริง)
  - [x] ปรับความโปร่งใสได้ (slider) ผ่าน `window_manager` → `setOpacity(0.0–1.0)`
  - [x] จำค่าความโปร่งใสและตำแหน่งหน้าต่างของ mini player
  - [ ] (ทางเลือก) เอฟเฟกต์ blur / Mica / Acrylic ด้วย `flutter_acrylic`
  - [ ] (ทางเลือก) โหมด click-through เมื่อโปร่งใสมาก ผ่าน `setIgnoreMouseEvents`
- [x] **ธีมและสีเน้น**
  - [x] ธีม Dark / Light / System (System ตามการตั้งค่าของ Windows) เก็บค่าที่เลือกไว้
  - [x] Accent color เลือกอิสระด้วย color picker (มีสีสำเร็จรูปให้ด้วย)
  - [x] คำนวณสีตัวอักษรบนปุ่มสีเน้นและสีข้อความสีเน้นให้อ่านออกในทั้งสองธีมโดยอัตโนมัติ
  - [x] พื้นที่วิดีโอเป็นสีเข้มเสมอทั้งสองธีม
- [x] **หน้า Settings เต็มรูปแบบ** (ตามบอร์ด "Settings" ในดีไซน์)
  - [x] 7 หมวด: General, Playback, Video, Mini player, Library, Shortcuts, About
  - [x] การ์ด Default player (ปุ่มเปิด Windows Default apps + จำนวนนามสกุลที่ตั้งแล้ว)
  - [ ] หน้าตั้งปุ่มลัด + Reset to defaults
  - [x] ธีมและ accent (ย้ายเข้าหน้า Settings แล้ว)
  - [ ] ยังไม่มีในหน้า Settings (รอฟีเจอร์ต้นทาง): ภาษา, Windows media controls (SMTC), ซับไตเติล, click-through, โฟลเดอร์ Library
- [x] **Sidebar นำทาง + ปุ่ม Home ลอยบนภาพ** (ออกแบบ B + C ตาม mockup)
  - [x] Sidebar ซ้ายทุกหน้า: Home / Library / Playlists / Player / Settings — 3 สถานะ เปิด (ไอคอน+ชื่อ) / ย่อ (ไอคอน) / ซ่อน จำสถานะไว้, ปุ่ม ☰ ที่แถบหัวและ `Ctrl+B` ซ่อน/แสดง, ลูกศรย่อ/ขยาย, หน้าต่างแคบ (<760px) แสดงเป็นไอคอนอัตโนมัติ, เต็มจอซ่อนอัตโนมัติ
  - [x] รวมเมนูซ้ายเดิมของหน้า Home เข้ากับ sidebar (ไม่ซ้อนสองชุด), เอาไอคอนบ้านเล็กๆ ที่แถบหัวออก, กดโลโก้/ชื่อแอปหรือกด `H` ไป Home
  - [x] ปุ่ม ‹ Home ลอยมุมซ้ายบนของภาพ เมื่อ sidebar ซ่อนหรือเต็มจอ: โผล่เมื่อขยับเมาส์/ตอนหยุด และจางหายพร้อมซ่อนเคอร์เซอร์เมื่อไม่ขยับเมาส์ 3 วินาทีขณะเล่น (เต็มจอมีปุ่มออกจากเต็มจอด้วย)
  - [x] แก้บั๊กปุ่มลัด: ปุ่มตัวอักษร/ลูกศร/Space ไม่ทำงานระหว่างพิมพ์ในช่องค้นหา (เดิมจะชนกัน) และโฟกัสกลับมาที่หน้าหลังคลิกออกจากช่องพิมพ์
  - [ ] ยังไม่ได้ทดสอบหน้าตา/การใช้งานจริงบนเครื่อง (ทดสอบด้วย widget test ของ sidebar และ unit test ของตัวกันปุ่มลัด)
- [x] **จัดหน้า Home ใหม่ (แบบ A จาก mockup)**: เนื้อหากว้างสูงสุด 1180px กึ่งกลาง ปรับตามพื้นที่ (ซ่อน/เปิด sidebar, หน้าต่างแคบ); การ์ด Continue ใบใหญ่ (ภาพใหญ่+ปุ่มเล่น+เวลา "เล่นเมื่อ...") + รายการเล่นต่ออีก 2 รายการ; แถวสถิติ (กราฟ 7 วันกว้าง + เพลงที่เล่นบ่อยของเดือน); แถบ "Recently added" จาก Library (ลิงก์ See all in Library, ถ้ายังไม่มีโฟลเดอร์แสดงปุ่ม Add a folder); แก้บั๊กหน้า Home/Library/Playlists หดเป็นคอลัมน์กลางจอหลังรวม sidebar (ยังไม่ได้ทดสอบหน้าตาจริง)
- [x] **Home แบบแท็บ All / Videos / Music + สุ่มวิดีโอ + หน้า History** (ตาม mockup)
  - [x] แท็บ All (ภาพรวม) / Videos / Music พร้อมจำนวนไฟล์; Continue แยกตามแท็บ
  - [x] **สุ่มวิดีโอ** ("Feeling lucky?" ในแท็บ All, "Random videos" 3 ใบในแท็บ Videos): Play / Roll again (ไม่ซ้ำกับที่เพิ่งโชว์) / สวิตช์ Only unwatched (ถ้าดูครบทุกเรื่องแล้วจะบอกและสุ่มจากทั้งหมด); ปุ่ม Shuffle all videos / Shuffle all music
  - [x] **เพลงเป็นหมวดของตัวเอง**: Play all / Shuffle + จำนวนเพลง/อัลบั้ม/ศิลปิน, Continue listening, Albums (จัดกลุ่มจาก tag อัลบั้ม+โฟลเดอร์, ปกจากเพลงแรก), Recently added songs, Listening history
  - [x] **หน้า History** (เมนูที่ 5 ใน sidebar): จัดกลุ่ม Today / Yesterday / Earlier this week / Earlier, กรอง All/Videos/Music, ค้นหา, แถบความคืบหน้า, เมนู ⋮ (Play / Add to playlist / Remove from history), Clear history (ยืนยันก่อน), ไฟล์ที่หายแสดงจาง; ประวัติเก็บ 200 รายการ (เดิม 30)
  - [ ] ยังไม่ได้ทดสอบหน้าตา/การใช้งานจริงบนเครื่อง (ทดสอบ logic: ตัวสุ่ม, การจัดกลุ่มอัลบั้ม, การจัดกลุ่มประวัติ, เวลา)
- [ ] **Upscale วิดีโอแบบ real-time ด้วย GLSL shader** (Anime4K / FSR / FSRCNNX ผ่าน mpv `glsl-shaders`)
  - [ ] ทดลองก่อนว่า shader ทำงานกับ `media_kit` (render ผ่าน texture) บนเครื่องจริงได้ครบหรือไม่
  - [ ] ตัวสเกลพื้นฐานของ mpv (`scale`/`cscale`/`dscale` = `ewa_lanczossharp`/`spline36`, `deband`) เป็นค่าเริ่มต้นที่ดีขึ้น
  - [ ] แพ็กไฟล์ `.glsl` ไปกับแอปและ installer
  - [ ] Settings > Video: โหมด Off / Fast / Quality (ผ่าน `_setMpv` แบบเดียวกับ `setHwdec`)
  - [ ] ปิดอัตโนมัติเมื่อ `reducedLoad` (mini player/ย่อหน้าต่าง) หรือเครื่อง GPU อ่อน
- [ ] **กล่องลอยตั้งค่าด่วนในหน้าเล่น** (ปุ่มฟันเฟืองในแถบควบคุม): ปรับค่าที่ต้องเห็นผลบนภาพทันที — คุณภาพวิดีโอ, โหมด upscale (Off/Fast/Quality), ความเร็ว, ซับ/แทร็กเสียง (รวมหรือแทน `TracksButton` เดิม); เป็นการสลับชั่วคราว ส่วนค่าเริ่มต้นถาวรยังอยู่ในหน้า Settings เต็ม
- [ ] **ตั้งเวลาหยุดสื่อ (Sleep timer)** — 2 วิธี
  - [ ] นับถอยหลัง (Countdown): เลือกเวลา เช่น 15/30/45/60 นาที หรือกำหนดเอง แล้วหยุดเมื่อครบ
  - [ ] อิงนาฬิกา (Clock time): ตั้งเวลาเป้าหมาย เช่น 23:30 แล้วหยุดเมื่อถึงเวลานั้น (ถ้าเวลาผ่านไปแล้วของวันนี้ ให้ถือเป็นของพรุ่งนี้)
  - [ ] ตัวเลือกเสริม: หยุดเมื่อจบเพลง/ไฟล์ปัจจุบัน
  - [ ] ค่อยๆ ลดเสียง (fade out) ก่อนหยุด แล้ว pause (ไม่ปิดแอป)
  - [ ] แสดงเวลาที่เหลือ/ยกเลิกได้ ใช้ `DateTime` เป้าหมายเทียบนาฬิกา เพื่อไม่เพี้ยนตอนเครื่อง sleep/ปรับเวลา
  - [ ] ปุ่มเข้าถึงในหน้าเล่นหรือกล่องลอยตั้งค่าด่วน + ค่าเริ่มต้นใน Settings > Playback
  - [ ] ทำงานต่อได้เมื่ออยู่ใน mini player (ส่งสถานะผ่าน `mini_ipc.dart` หรือให้ตัวจับเวลาอยู่ฝั่งที่กำลังเล่น)
- [ ] ปรับแต่ง UI อื่นๆ

## 6. จุดที่ต้องระวัง
- UI เสียงและวิดีโอควรแยกโหมดกัน ไม่บังคับให้เหมือนกัน
- ทำ Milestone 1–2 ให้เสถียรก่อนเพิ่มฟีเจอร์
- Default app ต้องผ่าน installer เท่านั้น รัน `flutter run` หรือเปิด exe ตรงๆ จะไม่ลงทะเบียนครบ
- ถ้าแจกจ่ายให้คนอื่น Windows SmartScreen อาจเตือนถ้าไม่มี code signing (ใช้เองไม่มีปัญหา)

## 7. Prompt เริ่มต้น (สำหรับ AI ช่วยเขียนโค้ด)
> สร้างโปรเจกต์ Flutter Desktop (Windows เท่านั้น) ชื่อ NSL Media Player เป็น media player เล่นไฟล์เสียงและวิดีโอ ใช้ `media_kit`, `media_kit_video`, `media_kit_libs_windows_video`, `window_manager`, `desktop_drop`, `file_picker` ขั้นแรกทำ: (1) หน้าหลักที่เล่นไฟล์เดียวได้ มี play/pause, seek bar, volume, ความเร็ว (2) รองรับลากไฟล์มาวางและรับ path จาก command-line args (3) ปุ่มลัดคีย์บอร์ดและ fullscreen แยกโค้ดเป็น `player_controller`, `ui/`, `services/` ยังไม่ต้องทำ playlist
