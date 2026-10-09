import socket
import unittest

from app import app


class FlashSaleTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_home(self):
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['message'], 'Welcome to Big Sale!')
        self.assertEqual(response.json['pod'], socket.gethostname())
        self.assertIsInstance(response.json['ts'], (int, float))

    def test_buy_with_user(self):
        response = self.client.get('/buy?user=123')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['status'], 'success')
        self.assertEqual(response.json['user'], '123')
        self.assertIn(response.json['item'], ['Smartphone', 'Shoes', 'Headphones', 'Laptop'])
        self.assertEqual(response.json['served_by_pod'], socket.gethostname())
        self.assertRegex(response.json['time'], r'^\d{2}:\d{2}:\d{2}$')

    def test_buy_with_generated_user(self):
        response = self.client.get('/buy')
        self.assertEqual(response.status_code, 200)
        self.assertRegex(response.json['user'], r'^user\d+$')

    def test_health(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {'status': 'healthy', 'pod': socket.gethostname()})

    def test_unknown_route(self):
        self.assertEqual(self.client.get('/missing').status_code, 404)


if __name__ == '__main__':
    unittest.main()
