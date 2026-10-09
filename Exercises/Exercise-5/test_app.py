import unittest

from app import app


class FlaskTests(unittest.TestCase):
    def test_home(self):
        response = app.test_client().get('/')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_data(as_text=True),
                         'Hello, this is a secure Flask application running inside a Docker container!')

    def test_missing_route(self):
        self.assertEqual(app.test_client().get('/missing').status_code, 404)


if __name__ == '__main__':
    unittest.main()
