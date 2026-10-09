import unittest

from app import app


class AboutTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_about(self):
        response = self.client.get('/about')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {
            'name': 'Simple REST API',
            'version': '1.0',
            'description': 'This is a simple REST API built with Flask.',
        })

    def test_missing_route(self):
        self.assertEqual(self.client.get('/missing').status_code, 404)

    def test_about_is_get_only(self):
        self.assertEqual(self.client.post('/about').status_code, 405)


if __name__ == '__main__':
    unittest.main()
