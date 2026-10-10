import unittest

from app import app


class TestApp(unittest.TestCase):
    def test_home(self):
        response = app.test_client().get('/')
        print(response.data.decode('utf-8'))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data.decode('utf-8'), 'Hello, Jenkins Multi-Stage Pipeline!')

    def test_unknown_route(self):
        self.assertEqual(app.test_client().get('/missing').status_code, 404)


if __name__ == '__main__':
    unittest.main()
