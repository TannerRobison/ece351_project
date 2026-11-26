"""Image experiments using the team's sng_controller packet protocol."""
import argparse
import csv
import math
import struct
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SEEDS = (0xACE1, 0x1D2C, 0x5EED)
TAPS = (0xB400, 0xD008, 0x8016)
MAPS = (0x02A8D31679CE4F5B, 0xB649A32017F5DEC8, 0x809EB7DFC3A16524)


def load_tables():
    tables = []
    for name in ('a', 'b', 's'):
        lines = (ROOT / f'lut_{name}.mem').read_text().splitlines()
        values = [int(t, 16) for line in lines for t in line.split('//')[0].split()]
        if len(values) != 2048 or any(v < 0 or v > 65535 for v in values):
            raise ValueError(f'Invalid lut_{name}.mem')
        tables.append(np.array(values, dtype=np.int64))
    return tables


def nearest(table, probability):
    return int(np.argmin(np.abs(table - probability * 65535)))


def packet(codes, seeds, length):
    if len(codes) != 3 or any(not 0 <= x <= 2047 for x in codes):
        raise ValueError('Three codes in 0..2047 required')
    if len(seeds) != 3 or any(not 1 <= x <= 65535 for x in seeds):
        raise ValueError('Three nonzero 16-bit seeds required')
    if not 0 <= length <= 65535:
        raise ValueError('L must fit in 16 bits')
    return b'\xA5' + struct.pack('<7H', *codes, *seeds, length)


def request(port, codes, seeds, length):
    data = packet(codes, seeds, length)
    if port.write(data) != len(data):
        raise OSError('Incomplete serial write; reset board before retrying')
    response = bytearray()
    deadline = time.monotonic() + 3.0
    while len(response) < 10 and time.monotonic() < deadline:
        response.extend(port.read(10 - len(response)))
    if len(response) != 10:
        raise TimeoutError('Incomplete reply. Reset board; check port and NEW bitstream. '
                           'Do not retry blindly: protocol has no response framing.')
    counts = struct.unpack('<5H', response)
    if any(c > length for c in counts):
        raise ValueError('Count exceeds L; likely wrong bitstream or serial misalignment')
    return counts


def random_values(seed, taps, mapping, length):
    """Exact uploaded Fibonacci LFSR and bit wiring; sample BEFORE advancing."""
    state = seed or 1
    values = np.empty(length, dtype=np.uint16)
    for k in range(length):
        values[k] = sum(((state >> ((mapping >> (4*i)) & 15)) & 1) << i
                        for i in range(16))
        feedback = bin(state & taps).count('1') & 1
        state = ((state << 1) & 65535) | feedback
    return values


class Model:
    """Software reference of SNG arithmetic, not UART or RTL simulation."""
    def __init__(self, tables):
        self.tables = tables
        self.cache = {}

    def run(self, codes, seeds, length):
        packet(codes, seeds, length)
        key = (tuple(seeds), length)
        if key not in self.cache:
            self.cache[key] = [random_values(s, t, m, length)
                               for s, t, m in zip(seeds, TAPS, MAPS)]
        a, b, s = [r <= table[code] for r, table, code in
                   zip(self.cache[key], self.tables, codes)]
        return tuple(int(np.count_nonzero(v)) for v in (a, b, s, a & b, np.where(s, b, a)))


def psnr(reference, measured):
    mse = float(np.mean((np.asarray(reference, dtype=float) - measured) ** 2))
    return math.inf if mse == 0 else 10 * math.log10(255**2 / mse)


def pixels(values):
    return Image.fromarray(np.clip(np.rint(values), 0, 255).astype(np.uint8))


def comparison(panels, destination):
    # Fixed labeled panels preserve aspect ratio with letterboxing.
    canvas = Image.new('RGB', (280 * len(panels), 310), '#23262b')
    draw = ImageDraw.Draw(canvas)
    for index, (label, im) in enumerate(panels):
        im = im.copy()
        im.thumbnail((256, 256), Image.Resampling.NEAREST)
        # Enlarge small demonstration images with nearest-neighbor interpolation.
        factor = min(256 / im.width, 256 / im.height)
        im = im.resize((max(1, round(im.width*factor)), max(1, round(im.height*factor))),
                       Image.Resampling.NEAREST)
        x = index*280
        draw.text((x+12, 10), label, fill='white')
        canvas.paste(im, (x+12+(256-im.width)//2, 42+(256-im.height)//2))
    canvas.save(destination)


def run_images(args, tables, run):
    if args.image:
        with Image.open(args.image) as im:
            source = im.convert('L')
            source.thumbnail((args.size, args.size), Image.Resampling.LANCZOS)
    else:
        row = np.rint(np.linspace(0, 255, args.size)).astype(np.uint8)
        source = Image.fromarray(np.tile(row, (args.size, 1)))
    a = np.asarray(source, dtype=float)
    if args.mode == 'brightness':
        b = np.full(a.shape, 255 * args.gain)
        reference = a * args.gain
    else:
        if args.image_b:
            with Image.open(args.image_b) as im:
                second = im.convert('L').resize(source.size, Image.Resampling.LANCZOS)
        else:
            second = Image.fromarray(np.flipud(np.asarray(source).T)).resize(source.size)
        b = np.asarray(second, dtype=float)
        reference = (a+b)/2
    ca = np.array([nearest(tables[0], v/255) for v in a.flat]).reshape(a.shape)
    cb = np.array([nearest(tables[1], v/255) for v in b.flat]).reshape(b.shape)
    cs = nearest(tables[2], 0.5)
    pa, pb, ps = tables[0][ca]/65535, tables[1][cb]/65535, tables[2][cs]/65535
    encoded_reference = 255 * (pa*pb if args.mode == 'brightness' else (1-ps)*pa+ps*pb)
    args.out.mkdir(parents=True, exist_ok=True)
    source.save(args.out / 'input_a.png')
    if args.mode == 'blend':
        pixels(b).save(args.out / 'input_b.png')
    pixels(reference).save(args.out / 'expected.png')
    np.save(args.out / 'reference_float.npy', reference)
    panels = [('Input A', source)]
    if args.mode == 'blend':
        panels.append(('Input B', pixels(b)))
    panels.append(('Expected (float reference)', pixels(reference)))
    backend = 'MODEL' if args.model else 'FPGA'
    print(f'{backend}; S code={cs}, P(S)={ps:.8f}; seeds={SEEDS}')
    with (args.out/'metrics.csv').open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['backend', 'operation', 'L', 'width', 'height', 'seconds',
                         'psnr_float_dB', 'psnr_display_dB', 'psnr_encoded_reference_dB'])
        for length in args.lengths:
            measured = np.empty(a.shape, dtype=float)
            all_counts = np.empty(a.shape+(5,), dtype=np.uint16)
            start = time.monotonic()
            for y in range(a.shape[0]):
                for x in range(a.shape[1]):
                    counts = run((int(ca[y,x]), int(cb[y,x]), cs), SEEDS, length)
                    all_counts[y,x] = counts
                    measured[y,x] = 255*counts[3 if args.mode == 'brightness' else 4]/length
                print(f'{backend} L={length}: row {y+1}/{a.shape[0]}', end='\r', flush=True)
            elapsed = time.monotonic()-start
            rendered = pixels(measured)
            score = psnr(reference, measured)
            writer.writerow([backend, args.mode, length, source.width, source.height, elapsed,
                             score, psnr(reference, np.asarray(rendered, dtype=float)),
                             psnr(encoded_reference, measured)])
            handle.flush()
            rendered.save(args.out/f'{backend.lower()}_L{length}.png')
            np.save(args.out/f'counts_L{length}.npy', all_counts)
            panels.append((f'{backend} L={length}\nPSNR={score:.2f} dB', rendered))
            print(f'\nL={length}: PSNR={score:.2f} dB, {elapsed:.1f}s')
    comparison(panels, args.out/'comparison.png')
    print(f'Open {args.out.resolve()/"comparison.png"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', help='COM5 on Windows; /dev/cu... on Mac')
    parser.add_argument('--model', action='store_true', help='Software reference only; no board')
    parser.add_argument('--test', action='store_true', help='Check known counts against Python model')
    parser.add_argument('--image', type=Path)
    parser.add_argument('--image-b', type=Path)
    parser.add_argument('--mode', choices=('brightness', 'blend'), default='brightness')
    parser.add_argument('--gain', type=float, default=0.35)
    parser.add_argument('--size', type=int, default=32)
    parser.add_argument('--lengths', type=int, nargs='+', default=[256, 1024, 4096])
    parser.add_argument('--out', type=Path, default=Path('image_results'))
    args = parser.parse_args()
    if bool(args.port) == args.model:
        parser.error('Choose exactly one of --port or --model')
    if not 0 <= args.gain <= 1 or not 1 <= args.size <= 1024:
        parser.error('gain must be 0..1 and size must be 1..1024')
    if any(not 1 <= n <= 65535 for n in args.lengths):
        parser.error('Image stream lengths must be 1..65535')
    if args.image_b and args.mode != 'blend':
        parser.error('--image-b requires --mode blend')
    tables = load_tables()
    model = Model(tables)
    def execute(run):
        if args.test:
            codes = (1370, 1450, 1363)
            for length in (0, 1, 19, 65535):
                expected = model.run(codes, SEEDS, length)
                actual = run(codes, SEEDS, length)
                print(f'L={length}: expected={expected}; received={actual}')
                if tuple(actual) != expected:
                    raise ValueError('Counts differ from the uploaded project model')
            print('PASS: test counts match' + (' (software only)' if args.model else ' (board UART)'))
        else:
            run_images(args, tables, run)
    if args.model:
        execute(model.run)
    else:
        import serial
        with serial.Serial(args.port, 115200, timeout=0.2, write_timeout=3) as port:
            time.sleep(0.1)
            port.reset_input_buffer()
            execute(lambda codes, seeds, length: request(port, codes, seeds, length))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as exc:
        raise SystemExit(str(exc))
