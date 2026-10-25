"""Locate the optional native font-category API in the installed CapCut binary."""
import mmap
from pathlib import Path
import struct


VECTOR_TYPE = ('__ZNSt3__16vectorINS_4pairIN8material13PanelCategoryENS0_INS_10shared_ptr'
               'I21LocalFontResourceItemEENS_9allocatorIS6_EEEEEENS7_ISA_EEE')
FONT_SYMBOLS = {
    'gate': '__ZN8lvabtest32enable_font_show_subCategory_870Ev',
    'categories': '__ZN19FontResourceManager27getAllPresetFontResourceNewEb',
    'copy': VECTOR_TYPE + 'C2ERKSC_',
    'destroy': VECTOR_TYPE + 'D1B7v160006Ev',
    'refresh': '__ZN27VEFontSpinComboBoxViewModel21_updateFontCategoriesEv',
    'clear': '__ZN5QListI8QVariantE5clearEv',
    'property': '__ZNK27VEFontSpinComboBoxViewModel14fontCategoriesEv',
}


def _arm64_slice(data):
    if data[:4] == b'\xcf\xfa\xed\xfe':
        if struct.unpack_from('<I', data, 4)[0] != 0x0100000c:
            raise ValueError('Not arm64')
        return 0, len(data)
    if data[:4] not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        raise ValueError('Not Mach-O')
    wide = data[:4] == b'\xca\xfe\xba\xbf'
    count = struct.unpack_from('>I', data, 4)[0]
    if count > 64:
        raise ValueError('Invalid architecture table')
    for i in range(count):
        pos = 8 + i * (32 if wide else 20)
        cpu = struct.unpack_from('>I', data, pos)[0]
        offset, size = struct.unpack_from('>QQ' if wide else '>II', data, pos + 8)
        if cpu == 0x0100000c and size >= 32 and offset + size <= len(data):
            return offset, size
    raise ValueError('No arm64 slice')


def read_native_symbols(path, names):
    """Resolve local nlist symbols without running a debugger in the editor."""
    with Path(path).open('rb') as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as data:
        base, length = _arm64_slice(data)
        if data[base:base + 4] != b'\xcf\xfa\xed\xfe':
            raise ValueError('Unsupported slice')
        count, command_size = struct.unpack_from('<II', data, base + 16)
        if count > 10000 or command_size > length - 32:
            raise ValueError('Invalid load commands')
        pos = base + 32
        text = symbols = None
        for _ in range(count):
            command, size = struct.unpack_from('<II', data, pos)
            if size < 8 or pos + size > base + 32 + command_size:
                raise ValueError('Invalid load command')
            if command == 2 and size >= 24:
                symbols = struct.unpack_from('<IIII', data, pos + 8)
            elif command == 0x19 and size >= 72 and data[pos + 8:pos + 24].rstrip(b'\0') == b'__TEXT':
                text = struct.unpack_from('<QQQQ', data, pos + 24)
            pos += size
        if not text or not symbols:
            return {}
        symoff, nsyms, stroff, strsize = symbols
        vmaddr, vmsize, fileoff, filesize = text
        if (symoff + nsyms * 16 > length or stroff + strsize > length or
                fileoff + filesize > length):
            raise ValueError('Invalid symbol table')
        found = {}
        for key, name in names.items():
            needle = name.encode('ascii') + b'\0'
            at = data.find(needle, base + stroff, base + stroff + strsize)
            if at < 0 or (at > base + stroff and data[at - 1] != 0):
                continue
            index = struct.pack('<I', at - base - stroff)
            entry, limit = base + symoff, base + symoff + nsyms * 16
            while True:
                entry = data.find(index, entry, limit)
                if entry < 0:
                    break
                if (entry - base - symoff) % 16 == 0:
                    _, kind, section, _, value = struct.unpack_from('<IBBHQ', data, entry)
                    if not kind & 0xe0 and kind & 0x0e == 0x0e and section and vmaddr <= value < vmaddr + vmsize:
                        offset = fileoff + value - vmaddr
                        if offset + 16 <= fileoff + filesize:
                            code = bytes(data[base + offset:base + min(offset + 256, fileoff + filesize)])
                            found[key] = {'offset': value - vmaddr, 'prefix': code[:16].hex(), 'code': code}
                            break
                entry += 1
        return found


def _has_category_stride(code, subtract=False):
    operation = 0xd1000000 if subtract else 0x91000000
    for (word,) in struct.iter_unpack('<I', code[:len(code) // 4 * 4]):
        if (word & 0xffc00000 == operation and (word >> 10) & 0xfff == 144 and
                word & 31 == (word >> 5) & 31):
            return True
    return False


def font_bridge_config(app):
    """Unsupported binaries keep their own font UI; font support never blocks launch."""
    try:
        symbols = read_native_symbols(Path(app) / 'Contents/Frameworks/libVECreator.dylib', FONT_SYMBOLS)
        if set(symbols) != set(FONT_SYMBOLS):
            return None
        # Check the instantiated vector's actual element stride before accessing
        # its category metadata. Do not assume an ABI after a CapCut upgrade.
        if not _has_category_stride(symbols['copy']['code']) or not _has_category_stride(symbols['destroy']['code'], True):
            return None
        if not _has_model_layout(symbols['refresh']['code'], symbols['property']['code']):
            return None
        return {key: {k: v for k, v in value.items() if k != 'code'} for key, value in symbols.items()}
    except (OSError, ValueError, struct.error, OverflowError):
        return None


def _has_model_layout(refresh, getter):
    # Prove both the enable flag and the owning QList layout used by the bridge.
    refresh_words = set(struct.unpack('<' + 'I' * (len(refresh) // 4), refresh[:len(refresh) // 4 * 4]))
    getter_words = set(struct.unpack('<' + 'I' * (len(getter) // 4), getter[:len(getter) // 4 * 4]))
    return ({0x39482009, 0xf9419408} <= refresh_words and
            {0xf9418c09, 0xf941900a, 0xf941940a} <= getter_words)
