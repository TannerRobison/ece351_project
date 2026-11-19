"""Send grayscale pixel codes to the Nexys 4 DDR and display its results."""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FULL_SCALE = 65535


def read_lut(name):
    path = ROOT / name
    values = [
        int(token, 16)
        for line in path.read_text().splitlines()
        for token in line.split("//", 1)[0].split()
    ]
    if len(values) != 2048 or any(not 0 <= value <= FULL_SCALE for value in values):
        raise ValueError(f"{path.name} must contain 2048 hexadecimal thresholds")
    return values


def nearest_code(table, threshold):
    return min(range(len(table)), key=lambda code: abs(table[code] - threshold))


def request_count(port, code_a, code_b):
    request = bytes([0xA5, code_a & 0x7F, code_a >> 7, code_b & 0x7F, code_b >> 7])
    port.write(request)
    response = port.read(2)
    if len(response) != 2:
        raise TimeoutError("No complete reply. Check the COM port and program image_top.bit.")
    return int.from_bytes(response, "little")


def to_pixel(count):
    return round(count * 255 / FULL_SCALE)


def display_results(source, output, gain):
    from PIL import Image, ImageDraw

    width, height = source.size
    zoom = max(1, 256 // max(width, height))
    panel_size = (width * zoom, height * zoom)
    panel_width, panel_height = panel_size
    preview = Image.new("RGB", (2 * panel_width + 36, panel_height + 52), "#23262b")
    draw = ImageDraw.Draw(preview)
    for x, image, title in (
        (12, source, "Original grayscale"),
        (24 + panel_width, output, f"FPGA output ({gain:.1%} gain)"),
    ):
        draw.text((x, 12), title, fill="white")
        preview.paste(image.resize(panel_size, Image.Resampling.NEAREST), (x, 34))
    output.save("fpga_output.png")
    preview.save("comparison.png")
    print("Saved fpga_output.png and comparison.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Windows example: COM5")
    parser.add_argument("--gain", default=0.35, type=float)
    parser.add_argument("--image", type=Path, help="Defaults to a built-in 32×32 grayscale ramp")
    parser.add_argument("--test", action="store_true", help="Send A code 1200 once")
    args = parser.parse_args()
    if not 0 <= args.gain <= 1:
        parser.error("--gain must be between 0 and 1")
    if args.test and args.image:
        parser.error("choose --test or --image")

    import serial
    from PIL import Image

    table_a = read_lut("lut_a.mem")
    table_b = read_lut("lut_b.mem")
    code_b = nearest_code(table_b, args.gain * FULL_SCALE)
    gain = table_b[code_b] / FULL_SCALE
    print(f"B code {code_b}, threshold {table_b[code_b]:04X}, gain {gain:.5f}")

    with serial.Serial(args.port, 115200, timeout=2, write_timeout=2) as port:
        port.reset_input_buffer()
        if args.test:
            code_a = 1200
            count = request_count(port, code_a, code_b)
            expected = table_a[code_a] * gain
            print(f"A code {code_a}, threshold {table_a[code_a]:04X}")
            print(f"Ideal count {expected:.1f}, FPGA count {count:04X} hex ({count} decimal)")
            print(f"FPGA probability {count / FULL_SCALE:.5f}, output pixel {to_pixel(count)}")
            return

        if args.image:
            with Image.open(args.image) as photo:
                source = photo.convert("L")
                source.thumbnail((32, 32), Image.Resampling.LANCZOS)
        else:
            source = Image.new("L", (32, 32))
            source.putdata([round(x * 255 / 31) for _ in range(32) for x in range(32)])

        codes = [nearest_code(table_a, pixel * 257) for pixel in range(256)]
        width, height = source.size
        output_pixels = []
        for index, pixel in enumerate(source.getdata(), start=1):
            count = request_count(port, codes[pixel], code_b)
            output_pixels.append(to_pixel(count))
            if index % width == 0:
                print(f"Processed row {index // width}/{height}", end="\r", flush=True)
        print()

    output = Image.new("L", source.size)
    output.putdata(output_pixels)
    display_results(source, output, gain)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
