# Проверка закреплённого FFmpeg 8.0.1

Официальный архив FFmpeg 8.0.1 собран из исходников на Linux x86_64 для проверки ядра. SHA256 совпадает с `Config/ffmpeg.env`: `05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`.

FFmpeg и FFprobe реально запускаются и сообщают версию 8.0.1. Лицензия из `ffmpeg -L`: LGPL 2.1 or later. Отключены GPL/nonfree/version3/autodetect/network. FFmpeg и zlib связаны статически; libc/libm остаются системными. Разрешены протоколы file/pipe.

Полный `scripts/verify-development.sh` выполнен: 39 тестов ядра прошли (полный прогон после добавления проверки декодирования), один ImageIO явно пропущен на Linux; импорт 5/5, состояние/пресеты 12/12, Python 26/26. Реально сконвертированы с обрезкой/масштабированием и проверкой результата: MP4, MOV, MKV, AVI, M4V, TS, M4A, AAC, AIFF, FLAC, WAV, PNG, JPEG. Нечётные размеры 7×5 PNG/JPEG и чёрные поля aspect-fit проверены декодированием.

WebM, MP3, OGG, Opus, WebP недоступны в этой минимальной LGPL-конфигурации и явно перечислены как непроверенные. Отдельный прогон с Debian FFmpeg 5.1.9 GPL-enabled, только для тестов, проверил все 18 профилей, включая WebP.

Это **не проверка готового macOS приложения**: Linux static test configuration отличается от release shared dylib configuration. Не проверены Xcode, VideoToolbox, ImageIO, архитектура Mach-O, упаковка, Gatekeeper и нотариализация. Тестовые Linux-бинарники не включаются в поставку.

Артефакты экспериментальной сборки хранятся в `/tmp/mediaforge-ffmpeg-8.0.1-linux`, не в Git. История восстановления фонового процесса и разграничение проверок записаны в [журнале](<../DEVELOPMENT_LOG.md>).
