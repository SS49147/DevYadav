import unittest

import product_catalog
import shopping_cart


class CatalogTests(unittest.TestCase):
    def test_exact_product_list(self):
        response = product_catalog.app.test_client().get('/products')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), product_catalog.products)

    def test_unknown_route(self):
        self.assertEqual(product_catalog.app.test_client().get('/missing').status_code, 404)


class CartTests(unittest.TestCase):
    def setUp(self):
        shopping_cart.cart.clear()
        self.client = shopping_cart.app.test_client()

    def tearDown(self):
        shopping_cart.cart.clear()

    def test_empty_cart(self):
        response = self.client.get('/cart')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), [])

    def test_add_source_item(self):
        item = {'id': 1, 'name': 'Laptop', 'quantity': 1}
        response = self.client.post('/cart', json=item)
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.get_json(), [item])
        self.assertEqual(self.client.get('/cart').get_json(), [item])

    def test_invalid_json_does_not_change_cart(self):
        response = self.client.post('/cart', data='{', content_type='application/json')
        self.assertEqual(response.status_code, 400)
        self.assertEqual(shopping_cart.cart, [])


if __name__ == '__main__':
    unittest.main()
