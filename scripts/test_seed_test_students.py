import unittest
from collections import Counter
from seed_test_students import plan, CLASSES

class SeedPlanTest(unittest.TestCase):
    def test_100(self):
        rows=plan(100)
        self.assertEqual(len(rows),100)
        self.assertEqual(len(set(n for n,c in rows)),100)
        counts=Counter(c for n,c in rows)
        self.assertEqual(set(counts),set(CLASSES))
        self.assertEqual(sorted(counts.values()),[9]*10+[10])
    def test_bounds(self):
        for n in [0,101]:
            with self.assertRaises(ValueError):
                plan(n)
