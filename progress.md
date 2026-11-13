# NSL Resonance — Progress

Last updated: 2026-11-13
Overall status: Phase 1-5, 9 done, Phase 7 ทำเฉพาะ acrylic, Phase 10 done, Phase 11a-d, 12 done (Phase 12.5 Private mode รอยืนยัน) (Phase 6 พักไว้, Phase 8 ค้าง, Milestone 7 ไว้ทีหลัง)

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

### Milestone 6: Photos & Books บน PC (เพิ่ม 2026-11-12 — ผู้ใช้เลือก: PDF ก่อน EPUB ทีหลัง, ทำบน PC ก่อนต่อ Hub)
### Phase 9: ออกแบบ UI ส่วนใหม่ (artifact) — [x] done (2026-11-12)
- [x] ออกแบบหน้า Photos / ตัวดูรูป / ชั้นหนังสือ / ตัวอ่าน PDF / Home-sidebar 4 ชนิด + แถบ Now playing เป็น artifact "NSL Resonance — Photos & Books Design" (https://claude.ai/artifact/6TQysy21QuvvhzhvgaGuhM); ผู้ใช้สั่งเริ่มลงมือส่วนสื่อใหม่ก่อน ส่วนการเชื่อมต่อมือถือ (Milestone 7) ไว้ทีหลัง
- ไม่ได้ออกแบบ: หน้าตั้งค่าโฟลเดอร์รูป/PDF, สไลด์โชว์เต็มจอ, หน้าแก้ไขอัลบั้ม
### Phase 10: ขยายโมเดล Library เป็น 4 ชนิด — [x] done (2026-11-12)
- [x] `media_types.dart`: `MediaKind` (audio/video/image/pdf), `kindOf`, `isLibraryFile`; `isSupportedMedia` ยังหมายถึง "เล่นได้" (เสียง/วิดีโอ) เท่านั้น รูป/PDF จึงไม่เข้าคิวเล่นเมื่อเปิดโฟลเดอร์หรือลากไฟล์
- [x] `LibraryService`: เก็บทุกชนิดใน `_all`, `items` ยังเป็นเฉพาะที่เล่นได้ (ทุกหน้าเดิมจึงไม่เปลี่ยน), เพิ่ม `images`/`books`/`imageCount`/`bookCount`; รูป/PDF ใช้ชื่อไฟล์เป็นชื่อ (รายละเอียด EXIF/PDF มาพร้อมตัวดู); index เก่าถูกสแกนใหม่ครั้งเดียวในเบื้องหลัง (`libraryKindsVersion`), mini player โปรเซสแยกไม่สแกน (`autoRescan: false`)
- [x] sidebar เพิ่ม Photos และ Books (หน้า placeholder `kind_pages.dart` แสดงจำนวนที่เจอ รอ Phase 11-12); ยังไม่ได้ปรับ Home (แท็บ Photos/Books) — ไปพร้อมหน้าจริง
- [x] test เพิ่ม 5 ข้อ (`test/media_kinds_test.dart`) รวม 139 ผ่าน, analyze ไม่มี error/warning, build release + เปิดแอปผ่าน; ยังไม่ได้ลองกดหน้า Photos/Books จริง
- หมายเหตุ: ไฟล์ HEIC/HEIF ยังไม่ถูกนับเป็นรูป (เพิ่มใน Phase 11 พร้อมตัวแปลง)
### Phase 11: รูปภาพ (Photos, อัลบั้ม, ตัวดูรูป, HEIC, กันรูปซ้ำ) — [x] done (11a-11d, 2026-11-13)
- [x] **11a (2026-11-12)** หน้า Photos แบบไทม์ไลน์ + ตัวดูรูป: `lib/ui/photos_view.dart` (จัดกลุ่มตามวันที่ถ่าย Today/Yesterday/วันที่, ปรับขนาดช่อง, ค้นหาชื่อ, ปุ่ม Add folder), `lib/ui/photo_viewer.dart` (ซูมด้วยล้อ/ลาก, ดับเบิลคลิกซูม, ลูกศร/Home/End/Esc, หมุนดู, แผงรายละเอียด I, แถบรูปย่อ, Show in folder, โหลดรูปข้างเคียงล่วงหน้า); อ่านวันที่ถ่ายจาก EXIF ตอนสแกน (`exif ^3.3.0`, อ่านแค่ 128 KB แรก, เก็บในดัชนีคีย์ `k`) ไม่มี EXIF ใช้วันที่แก้ไขไฟล์; รูปย่อใช้ `Image.file(cacheWidth)` (ยังไม่มีแคช PNG บนดิสก์)
  - test 13 ข้อ (`test/photos_test.dart`: วันที่ EXIF จากไฟล์ JPEG ที่สร้างขึ้น, จัดกลุ่ม, หน้า Photos, ตัวดู) รวม 152 ผ่าน, analyze ไม่มี error/warning, build release + เปิดแอปผ่าน
  - ยังไม่ได้ลองกับรูปจริงของผู้ใช้/จำนวนมาก (ความเร็วเลื่อน, การกินแรม) และไม่ได้ลองกดตัวดูจริง → Phase 8
- [x] **11b (2026-11-13)** อัลบั้ม + สไลด์โชว์:
  - หน้า Photos มีแท็บ Timeline / Albums / Folders: **Folders** = ทุกโฟลเดอร์ที่มีรูปเป็นอัลบั้มอัตโนมัติ (`folderAlbums`, ปกเป็นคอลลาจ 3 รูป); **Albums** = อัลบั้มที่ตั้งชื่อเอง (สร้าง/เปลี่ยนชื่อ/ลบ, ไฟล์จริงไม่ถูกลบ) เก็บที่ `%APPDATA%\NSL Media Player\photo_albums.json` โดยใช้ `PlaylistService` ตัวเดิมที่ปรับให้รับชื่อไฟล์/ชื่อเริ่มต้นได้ (ไม่เขียนซ้ำ)
  - โหมด Select (เลือกหลายรูปทั้งในไทม์ไลน์และในอัลบั้ม) → Add to album (เมนูเลือกอัลบั้ม/New album…) และ Remove from album; ตัวดูรูปมีปุ่ม Add to album ด้วย
  - ตัวดูรูป: สไลด์โชว์ (Space, เลือก 3/5/10/30 วินาที, วนรอบเมื่อถึงรูปสุดท้าย, กดเปลี่ยนรูปเองแล้วเริ่มนับเวลาใหม่), เต็มจอ (F/F11, Esc ออก), ปุ่ม Slideshow ที่หัวหน้าไทม์ไลน์/อัลบั้ม/โฟลเดอร์
  - แก้ 2 บั๊กที่เทสต์เจอระหว่างทำ: (1) หัวหน้า Photos ล้นจอเมื่อหน้าต่างแคบ → ให้ปุ่มตัดบรรทัดเอง (2) กล่องตั้งชื่ออัลบั้มทิ้ง TextEditingController เร็วเกินไป (error ตอนปิดกล่อง) → ย้ายไปอยู่ใน StatefulWidget ของกล่องเอง
  - test เพิ่มรวม 161 ผ่าน (`test/photo_albums_test.dart` 9 ข้อ), analyze ไม่มี error/warning, build release + เปิดแอปผ่าน; ยังไม่ได้ลองกดจริง (โดยเฉพาะ fullscreen ซึ่งเทสต์ไม่ได้ทดสอบเพราะเรียก `window_manager`) → Phase 8
- [x] **11c (2026-11-13)** แถบ Now playing ส่วนกลาง — เล่นเพลง/คลิปต่อได้ตอนดูรูป/อ่านหนังสือ:
  - `lib/ui/now_playing_dock.dart`: แถบล่างจอ (ปก/เฟรมวิดีโอ, ชื่อ, ก่อนหน้า/เล่น-หยุด/ถัดไป, แถบเวลา `SeekRow`, ความดัง, "Show picture" เมื่อเป็นวิดีโอแบบเสียงอย่างเดียว, เปิดตัวเล่น; จอแคบ <860px ซ่อนความดัง) แสดงทุกหน้ายกเว้นหน้า Player/เต็มจอ/mini และใต้ตัวดูรูป (`PhotoViewerPage(controller:)`)
  - `lib/services/hub_audio.dart` (`HubAudioOnly`): วิดีโอที่กำลังเล่นจะลดเป็น sound only (`vid=no` เดิม) เมื่อออกจากหน้า Player และคืนภาพเมื่อกลับมา; ยกเลิกเฉพาะที่ตัวเองเปิด (ถ้าผู้ใช้เปิด sound only เองไว้ก่อน จะไม่ไปปิดให้); ตั้งปิดได้ที่ Settings > Playback > "Sound only while browsing" (เปิดเป็นค่าเริ่มต้น); ไม่ทำงานเมื่อ mini player แยกโปรเซสเล่นอยู่
  - เปิดไฟล์ (Open file/ลากวาง) ตอนอยู่หน้า Photos/Books จะเล่นเป็นพื้นหลังแทนที่จะเด้งไปหน้า Player; ปิดได้ที่ Settings > Playback > "Keep browsing when a file opens" (เปิดเป็นค่าเริ่มต้น); เล่นจาก Library/Home/History ยังไปหน้า Player ตามเดิม
  - test เพิ่ม 7 ข้อ (`test/hub_audio_test.dart`) รวม 168 ผ่าน, analyze ไม่มี error/warning, build release + เปิดแอปผ่าน
  - **ยังไม่ได้เห็นแถบนี้จริง**: เทสต์สร้าง `NslPlayerController` ไม่ได้ (ต้องมี libmpv) จึงไม่มี widget test ของแถบ และไม่ได้ลองกดจริง → Phase 8: เปิดเพลงแล้วไปหน้า Photos (แถบขึ้นไหม, ปุ่มทำงานไหม), เปิดวิดีโอแล้วออกไปหน้า Library (เสียงต่อไหม, กลับมาภาพคืนไหม), กด Show picture, เปิดตัวดูรูปตอนเพลงเล่น
- [x] **11d (2026-11-13)** HEIC + duplicate pictures + thumbnail cache:
  - **HEIC/HEIF** are now pictures (`imageExtensions`). Flutter cannot decode them, so `lib/services/heic_converter.dart` converts to JPEG with the decoder Windows already has (PowerShell + WPF `BitmapDecoder`; needs the Store's "HEIF Image Extensions"), cached in `%APPDATA%\NSL Media Player\heic` keyed like thumbnails; one conversion at a time; the original is never touched. The viewer shows a spinner while converting and a hint if it fails; thumbnails of HEIC use the same converter.
  - **Thumbnail cache for pictures**: the Photos grid uses `ThumbnailService` (256 px PNG on disk + memory) for tiles up to ~300 px; bigger tiles and folder/album covers still decode the original; the viewer's thumbnail strip uses the cache too.
  - **Duplicates**: pictures keep their file size (`z`) in the index; only pictures sharing a size with another are SHA-1 hashed (`h`; `crypto` is now a direct dependency), in the background after a scan and from saved hashes on start. The oldest copy (by date taken) is kept; the extra copies are hidden on the timeline by default, with a "Hiding N duplicates" toggle in the header. Nothing is ever deleted. `libraryKindsVersion` is now 3, so an old index is rescanned once to get sizes.
  - tests +9 (`test/heic_duplicates_test.dart`: converter cache / failure / missing file using a fake converter; duplicate detection, keep-oldest, index round-trip, unreadable file); 177 pass, analyze has no errors/warnings, release build OK; the WPF conversion script was checked with a real file (icon to valid JPEG).
  - **Not verified on a real HEIC file** (none on this machine): that the Windows HEIF codec decodes it (some HEIC also need the "HEVC Video Extensions"), that it comes out the right way up (EXIF rotation may not carry over), and that the EXIF date is read from HEIC. Also not tried: scrolling a big photo folder with the thumbnail cache → Phase 8.
### Phase 12: ebook PDF (ชั้นหนังสือ, ตัวอ่าน, resume, bookmark, ค้นหา) — [x] done (2026-11-13)
- [x] Built to the Phase 9 design (boards "5 · Books — shelf" and "6 · PDF reader"; I first built from my own layout, then read the artifact and matched it). New dependency `pdfrx` (PDFium; `pdfium.dll` is bundled by the Windows build) and `crypto` stays direct.
- [x] **Shelf** (`lib/ui/books_view.dart`, replaces the placeholder `kind_pages.dart`): filter chips All / Reading / Not started / Finished, search by title, sort (Recently read / Title / Progress), "Continue reading" card with Resume, cover grid (3:4, progress strip on the cover, "Page x of y" / "Not started" / "Finished"), "Add folder" and "Open PDF" (opens a single file without adding it to the library).
- [x] **Covers**: `ThumbnailService` renders page 1 with PDFium (own queue, one at a time) and caches it on disk like other thumbnails.
- [x] **Reader** (`lib/ui/book_reader.dart`): continuous scrolling, side panel with Pages (thumbnails) / Marks / Contents (the PDF's outline), toolbar (back, panel, search, bookmark, zoom -/+, Dark pages), floating text search (n of m, previous/next, highlights), page slider with %, "Saved automatically", Now playing dock under it (music keeps playing). Keys: Ctrl+F search, Esc (close search, then leave), B bookmark, +/- zoom.
- [x] **Remembering** (`lib/services/book_service.dart`, `%APPDATA%\NSL Media Player\books.json`): last page, page count, last opened and bookmarks per file path (case-insensitive); saved a moment after you stop scrolling and when the reader closes; reopening goes to the saved page.
- [x] **Home**: a "Continue reading" row on Home > All (up to 4 unfinished books that are still in the library).
- tests +9 (`test/books_test.dart`: position, clamping, in-progress order, bookmarks, restart, damaged file, mark unread, shelf filters/search/empty); 186 pass, analyze has no errors/warnings, release build OK and the exe starts.
- **Not seen working with a real PDF yet** (no widget test can run PDFium): whether covers render, the reader opens/scrolls/zooms, search finds and highlights text, page thumbnails load, Dark pages looks right, the saved page is restored, and how a 500-page book behaves → Phase 8.
- Not done (design had them, kept for later): "Layout" button (single page / two pages), author under the title (PDF metadata is not read, so the shelf shows progress instead), search result snippet, rename bookmarks in the UI (the service supports it), "mark as unread" menu on the shelf, password-protected PDFs (shows "Can't open").
### Phase 12.5: Private mode (โหมดส่วนตัว ขอรหัสเข้า) — [ ] ร่างแผนแล้ว รอผู้ใช้ยืนยัน
- [ ] ดูรายละเอียดใน Plan.md (Milestone 6); ล็อกระดับแอปเท่านั้น ไม่เข้ารหัสไฟล์; ซ่อนจากทุกหน้า/ประวัติ/แคช/SMTC ตอนล็อก; ผลต่อ Hub ระบุไว้ใน Milestone 7
### Phase 13: EPUB — [ ] พักไว้ (ON HOLD) ไม่ทำจนกว่าผู้ใช้เรียก

### Milestone 7: Android + Hub (เพิ่ม 2026-11-12 — รอผู้ใช้ยืนยันลำดับก่อนเริ่ม; เลขเฟสเลื่อนหลังเพิ่ม Milestone 6)
### Phase 14: Hub server บน PC — [ ] not started
- [ ] โปรโตคอล REST `/v1` + WebSocket, **TLS ใบรับรองที่ PC สร้างเอง + ลายนิ้วมือใน QR**, จับคู่ด้วย QR ใช้ครั้งเดียว + token (แฮชที่ PC), เพิกถอนเครื่อง, Settings > Remote, unit test
- [ ] จับคู่ด้วยรหัส 8 ตัวอักษรที่ PC สร้าง (+ QR) พร้อมขั้นอนุมัติบน PC, จำกัดครั้งที่ผิด, ผูกกับใบรับรอง
- [ ] mDNS ประกาศบริการ, **เปิดพร้อม Windows + ถาดระบบ** (Hub ทำงานโดยไม่ต้องเปิดหน้าต่าง)
- [ ] โมเดลข้อมูลรองรับ 4 ชนิดสื่อ (เสียง/วิดีโอ/รูป/PDF) ตั้งแต่เริ่ม
### Phase 15: โครง Android + เชื่อมต่อ Hub — [ ] not started
- [ ] `flutter create --platforms=android .`, build APK, UI มือถือ, สแกน QR + mDNS
### Phase 16: A รีโมตครบ — [ ] not started
### Phase 17: B สตรีมจาก PC + เล่นต่อตอนปิดจอ — [ ] not started
### Phase 18: E1 ดาวน์โหลดออฟไลน์แบบต้นฉบับ — [ ] not started
### Phase 19: E2 เลือกคุณภาพ (แปลงที่ PC ด้วย ffmpeg) — [ ] not started
- [ ] ต้องตัดสินใจเรื่อง ffmpeg (แนบมากับแอป/ให้ชี้ตำแหน่ง, ขนาดตัวติดตั้ง, ไลเซนส์) ก่อนเริ่ม
### Phase 20: เล่นไฟล์ในเครื่องมือถือเอง — [ ] not started
### Phase 21: D อัปโหลดมือถือ → PC — [ ] not started
- [ ] รับไฟล์แบบสตรีม/ต่อจากที่ค้าง, โฟลเดอร์รับอัปโหลด (ใน Library), Wi-Fi อย่างเดียว, ความคืบหน้า, ลบต้นฉบับหลัง PC ยืนยัน, ความปลอดภัย (ล้างชื่อไฟล์, ไม่เขียนทับ, เช็คพื้นที่/ขนาด)
### Phase 22: C ซิงก์ resume/ประวัติ/playlist — [ ] not started
### Phase 23: ใช้นอกบ้านผ่าน VPN + ความปลอดภัย — [ ] not started

## Notes / Decisions / Blockers
- 2026-11-12: วางแผนการเชื่อมต่อมือถือ↔PC (เขียนใน Plan.md Milestone 7): ผู้ใช้ตัดสินใจ (1) TLS + ใบรับรองที่ PC สร้างเอง (2) PC เปิดพร้อม Windows + ถาดระบบ (3) ซิงก์ให้ PC เป็นแหล่งข้อมูลหลัก — ผมเสนอข้อกันของหาย (PC ชนะจุดที่ชนกัน แต่ของที่มือถือเพิ่มถูกรวม + แจ้งเมื่อมีอะไรถูกทับ) รอผู้ใช้ยืนยัน; ความเสี่ยงที่ต้องทดสอบตอน Phase 14-15: mpv บน Android สตรีมผ่านใบรับรอง self-signed ได้ไหม
- 2026-11-12: ผู้ใช้เพิ่มความต้องการ (ยังเป็นแผน ไม่มีโค้ด): (1) ขยาย Hub เป็นสื่อ 4 ชนิด + อัลบั้มรูป + ebook PDF (Milestone 6 บน PC ก่อน; EPUB ไว้ทีหลัง) พร้อมออกแบบ UI เป็น artifact; (2) ตอนดูรูป/อ่านหนังสือต้องเปิดเพลง/คลิปเล่นเป็น audio only ต่อได้ (แถบ Now playing ส่วนกลาง, ไม่เด้งไปหน้า Player) — ยังไม่ได้เขียนลง Plan.md รอผู้ใช้ดูแบบ; (3) มือถือดาวน์โหลดสื่อจาก PC ไว้ออฟไลน์ + เลือกคุณภาพ (ฟีเจอร์ E, Phase 18-19; เลขเฟสของ Milestone 7 เลื่อนเป็น 14-23)
- 2026-11-12: เพิ่ม Milestone 7 (Android + Hub) ตามที่ผู้ใช้ต้องการ: ใช้เองเครื่องเดียว แจก APK ธรรมดา; ขอบเขตรีโมต/สตรีม/ซิงก์ครบ A+B+C เหมือน Hub เก็บสื่อส่วนตัว + ฟีเจอร์ D อัปโหลดสื่อจากมือถือไปเก็บที่ PC (ผู้ใช้เพิ่มทีหลัง; Phase 21, ต้องหลัง Phase 20); Android เท่านั้น (iOS ไม่ทำ); Upscale ยังพักไว้ (ไม่ทำบนมือถือ); เครื่องมี Android SDK 36 พร้อม แต่ยังไม่มีโฟลเดอร์ `android/`. สมมติฐานที่ผมตั้ง (ผู้ใช้ยังไม่ได้ยืนยัน): ทำ Hub server บน PC ก่อน แล้วแอปมือถือเวอร์ชันแรกเป็นรีโมตล้วน, LAN ก่อน นอกบ้านใช้ Tailscale ทีหลัง
- 2026-11-12: ผู้ใช้สั่งเปลี่ยนชื่อโปรแกรมเป็น **NSL Resonance** เปลี่ยนชื่อที่แสดง (ชื่อหน้าต่าง/แถบหัว, Settings, installer: AppName/โฟลเดอร์ติดตั้ง/ชื่อไฟล์ Setup/รายการใน Default apps, ProductName ของ exe) ส่วนชื่อภายในคงเดิมโดยตั้งใจ: แพ็กเกจและ exe `nsl_media_player`, โฟลเดอร์ข้อมูล `%APPDATA%/NSL Media Player` (ย้ายแล้วข้อมูล library/playlists/thumbnails จะหาย), ProgID `NslMediaPlayer.File`, คีย์ `Software/NSL/MediaPlayer`, AppId ของ installer (ให้ติดตั้งทับของเดิมได้); installer ลบรายการ RegisteredApplications ชื่อเก่าให้ตอนอัปเกรด
- 2026-11-13: New machine set up: Flutter 3.47.9, VS 2026 (C++ tools), Rust 1.100 (installed via winget; needed by smtc_windows), Developer Mode on. `flutter build windows --release` OK (~12 min first build), 168 tests pass. Not installed (not needed yet): Inno Setup, Android SDK, ffmpeg. The cargokit `resolve_symlinks.ps1` prints a `Get-Item` path error during the build but the build still succeeds and `smtc_windows.dll` is produced.
- 2026-11-13: Fix found by the user (screenshot): Home showed two Now playing bars, its own old `_NowPlayingBar` plus the global dock from 11c. Removed the Home one (the `_MiniBanner` for the separate mini player stays); the dock now serves Home too.
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
