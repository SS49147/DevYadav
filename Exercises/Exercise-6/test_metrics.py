import unittest
from unittest.mock import patch

import delivery_metrics as metrics


class DeliveryMetricsTests(unittest.TestCase):
    def test_normal_values(self):
        with patch('delivery_metrics.random.randint', side_effect=[15, 12, 40]), patch('delivery_metrics.random.uniform', return_value=25):
            result = metrics.simulate_delivery()
        self.assertEqual(result, {'total': 67, 'pending': 15, 'on_the_way': 12, 'delivered': 40, 'time': 25})
        self.assertEqual(metrics.total_deliveries._value.get(), 67)
        self.assertEqual(metrics.pending_deliveries._value.get(), 15)
        self.assertEqual(metrics.on_the_way_deliveries._value.get(), 12)

    def test_high_pending_range(self):
        with patch('delivery_metrics.random.randint', side_effect=[75, 10, 50]) as randint:
            result = metrics.simulate_delivery('high_pending')
        self.assertEqual(randint.call_args_list[0].args, (50, 100))
        self.assertEqual(result['pending'], 75)
        self.assertEqual(result['total'], 135)

    def test_summary_observation(self):
        count = metrics.average_delivery_time._count.get()
        total = metrics.average_delivery_time._sum.get()
        with patch('delivery_metrics.random.uniform', return_value=42):
            metrics.simulate_delivery()
        self.assertEqual(metrics.average_delivery_time._count.get(), count + 1)
        self.assertEqual(metrics.average_delivery_time._sum.get(), total + 42)

    def test_controlled_slow_scenario(self):
        with patch('delivery_metrics.random.uniform', return_value=40) as uniform:
            result = metrics.simulate_delivery('high_pending_slow')
        uniform.assert_called_once_with(35, 45)
        self.assertEqual(result['time'], 40)


if __name__ == '__main__':
    unittest.main()
