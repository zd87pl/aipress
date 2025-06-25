import http from 'k6/http';
import { sleep, check } from 'k6';

// --- Test Configuration ---
const TARGET_URL = 'INPUT_HOSTNAME_HERE'; // Updated for test777
const VIRTUAL_USERS = 25; // Testing with 25 VUs
const DURATION = '30s';   // How long to run the test

export const options = {
  vus: VIRTUAL_USERS,
  duration: DURATION,
  thresholds: {
    // Define success criteria (optional but recommended)
    'http_req_failed': ['rate<0.01'], // http errors should be less than 1%
    'http_req_duration': ['p(95)<500'], // 95% of requests should be below 500ms
  },
};

// --- Test Logic ---
export default function () {
  // Simple GET request to the homepage
  const res = http.get(TARGET_URL);

  // Check if the request was successful (status code 200)
  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  // Add a short pause between requests per virtual user
  sleep(1);
}
