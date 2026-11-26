"""Host protocol and model regression checks. Does not simulate RTL."""
import struct
import unittest
import numpy as np
import project_images as app

class FakeSerial:
    def __init__(self, reply):
        self.reply = bytearray(reply)
        self.written = None
    def write(self, data):
        self.written = data
        return len(data)
    def read(self, n):
        # Force partial serial reads to exercise response assembly.
        data = self.reply[:min(3,n)]
        del self.reply[:len(data)]
        return data

class Tests(unittest.TestCase):
    def test_packet_and_partial_reply(self):
        port = FakeSerial(struct.pack('<5H', 11,16,5,9,13))
        counts = app.request(port, (1370,1450,1363), app.SEEDS, 19)
        self.assertEqual(counts, (11,16,5,9,13))
        self.assertEqual(port.written.hex(), 'a55a05aa055305e1ac2c1ded5e1300')
    def test_invalid_count(self):
        port = FakeSerial(struct.pack('<5H', 20,16,5,9,13))
        with self.assertRaises(ValueError):
            app.request(port, (1370,1450,1363), app.SEEDS, 19)
    def test_recorded_project_counts(self):
        model = app.Model(app.load_tables())
        # Counts recorded in the supplied design log for this RTL configuration.
        for length, counts in [(0,(0,0,0,0,0)),(1,(0,1,1,0,1)),
                               (19,(11,16,5,9,13)),
                               (65535,(37924,56045,32682,32465,46939))]:
            self.assertEqual(model.run((1370,1450,1363),app.SEEDS,length), counts)
    def test_psnr(self):
        self.assertTrue(np.isinf(app.psnr(np.array([1.,2.]),np.array([1.,2.]))))
        self.assertAlmostEqual(app.psnr(np.array([0.]),np.array([255.])),0)
    def test_ranges(self):
        for length in (-1,65536):
            with self.assertRaises(ValueError): app.packet((0,0,0),app.SEEDS,length)

if __name__ == '__main__':
    unittest.main()
