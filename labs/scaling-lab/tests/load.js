// Usage:
//   Ramp test (default):   k6 run -e ENDPOINT=/items/{id} tests/load.js
//   Constant load:         k6 run -e ENDPOINT=/io/good -e VUS=50 -e DURATION=60s tests/load.js
// {id} is replaced with a random id between 1 and 1,000,000 on every request.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8000';
const ENDPOINT = __ENV.ENDPOINT || '/items/{id}';
const STATS = ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'];

export const options = __ENV.VUS
  ? { vus: Number(__ENV.VUS), duration: __ENV.DURATION || '60s', summaryTrendStats: STATS }
  : {
      stages: [
        { duration: '30s', target: 20 },
        { duration: '1m', target: 100 },
        { duration: '1m', target: 200 },
        { duration: '30s', target: 0 },
      ],
      summaryTrendStats: STATS,
    };

export default function () {
  const id = String(1 + Math.floor(Math.random() * 1000000));
  const res = http.get(BASE + ENDPOINT.split('{id}').join(id), { timeout: '10s' });
  check(res, { 'status is 200': (r) => r.status === 200 });
}
