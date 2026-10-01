"""Prove APK signature structures are absent; verifier failure is not that proof."""
from pathlib import Path
import struct
import zipfile


def assert_unsigned_apk(path: Path):
    try:
        data = path.read_bytes()
        end = data.rfind(b'PK\x05\x06', max(0, len(data) - 65557))
        if end < 0 or len(data) < end + 22:
            raise ValueError('Missing ZIP end record')
        signature, disk, central_disk, disk_count, count, central_size, central_offset, comment_size = struct.unpack_from('<4s4H2IH', data, end)
        if disk or central_disk or disk_count != count or count == 65535 or central_offset == 0xFFFFFFFF or central_size == 0xFFFFFFFF:
            raise ValueError('Split/ZIP64 archives cannot establish unsigned status')
        if end + 22 + comment_size != len(data) or central_offset + central_size != end:
            raise ValueError('Malformed/trailing ZIP data')
        with zipfile.ZipFile(path) as archive:
            entries = sorted(archive.infolist(), key=lambda item: item.header_offset)
            names = [item.filename for item in entries]
            if len(entries) != count or len(set(names)) != len(names) or 'AndroidManifest.xml' not in names:
                raise ValueError('APK entry list is missing, duplicated or inconsistent')
            for name in names:
                upper = name.upper()
                if upper.startswith('META-INF/') and (upper == 'META-INF/MANIFEST.MF' or upper.endswith(('.SF', '.RSA', '.DSA', '.EC')) or upper.rsplit('/', 1)[-1].startswith('SIG-')):
                    raise ValueError('JAR/v1 signature material is present')
            cursor = 0
            for entry in entries:
                if entry.header_offset != cursor or cursor + 30 > central_offset:
                    raise ValueError('Unaccounted ZIP data or APK signing block')
                header = struct.unpack_from('<4s5H3I2H', data, cursor)
                magic, version, flags, method, timestamp, date, crc, compressed, size, name_len, extra_len = header
                if magic != b'PK\x03\x04' or flags != entry.flag_bits or method != entry.compress_type or flags & 1:
                    raise ValueError('Invalid/encrypted local ZIP record')
                encoding = 'utf-8' if flags & 0x800 else 'cp437'
                name_start = cursor + 30
                if data[name_start:name_start + name_len] != entry.orig_filename.encode(encoding):
                    raise ValueError('Local/central ZIP filename mismatch')
                if compressed == 0xFFFFFFFF or size == 0xFFFFFFFF:
                    raise ValueError('ZIP64 local record unsupported')
                if not flags & 8 and (crc, compressed, size) != (entry.CRC, entry.compress_size, entry.file_size):
                    raise ValueError('Local/central ZIP size or CRC mismatch')
                cursor = name_start + name_len + extra_len + entry.compress_size
                if flags & 8:
                    if data[cursor:cursor + 4] == b'PK\x07\x08':
                        cursor += 4
                    if cursor + 12 > central_offset or struct.unpack_from('<3I', data, cursor) != (entry.CRC, entry.compress_size, entry.file_size):
                        raise ValueError('Malformed ZIP data descriptor')
                    cursor += 12
                if cursor > central_offset:
                    raise ValueError('Overlapping ZIP records')
            # v2/v3 APK signing blocks occupy bytes between file data and the central
            # directory. Requiring adjacency rejects intact AND damaged block magic.
            if cursor != central_offset:
                raise ValueError('APK signing block or unaccounted ZIP data is present')
            bad_entry = archive.testzip()
            if bad_entry:
                raise ValueError('ZIP payload CRC mismatch: ' + bad_entry)
    except (OSError, struct.error, UnicodeError, zipfile.BadZipFile, RuntimeError, NotImplementedError) as error:
        raise ValueError('APK structure cannot establish unsigned status: ' + str(error)) from error
