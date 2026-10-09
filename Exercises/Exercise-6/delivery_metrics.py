import os
import random
import time

from prometheus_client import Gauge, Summary, start_http_server

total_deliveries = Gauge('total_deliveries', 'Total number of deliveries')
pending_deliveries = Gauge('pending_deliveries', 'Number of pending deliveries')
on_the_way_deliveries = Gauge('on_the_way_deliveries', 'Number of deliveries on the way')
average_delivery_time = Summary('average_delivery_time', 'Average delivery time in seconds')


def simulate_delivery(mode='normal'):
    pending = random.randint(50, 100) if mode.startswith('high_pending') else random.randint(10, 20)
    on_the_way = random.randint(5, 20)
    delivered = random.randint(30, 70)
    avg_time = random.uniform(35, 45) if mode == 'high_pending_slow' else random.uniform(15, 45)
    total = pending + on_the_way + delivered
    total_deliveries.set(total)
    pending_deliveries.set(pending)
    on_the_way_deliveries.set(on_the_way)
    average_delivery_time.observe(avg_time)
    print(f'Total: {total}; pending: {pending}; on the way: {on_the_way}; time: {avg_time:.2f}s', flush=True)
    return {'total': total, 'pending': pending, 'on_the_way': on_the_way, 'delivered': delivered, 'time': avg_time}


if __name__ == '__main__':
    mode = os.environ.get('DELIVERY_MODE', 'normal')
    if mode not in ('normal', 'high_pending', 'high_pending_slow'):
        raise ValueError('Unknown DELIVERY_MODE')
    start_http_server(8000, addr='0.0.0.0')
    while True:
        simulate_delivery(mode)
        time.sleep(1)
