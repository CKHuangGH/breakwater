import http from 'k6/http';
import { Counter, Rate, Trend } from 'k6/metrics';

const offeredOperations = new Counter('offered_operations');
const successfulOperations = new Counter('successful_operations');
const sloOperations = new Counter('slo_operations');
const operationSuccessRate = new Rate('operation_success_rate');
const operationGoodputRate = new Rate('operation_goodput_rate');
const operationDuration = new Trend('operation_duration', true);

const products = [
  '0PUK6V6EV0',
  '1YMWWN1N4O',
  '2ZYFJ3GM2N',
  '66VCHSJNUP',
  '6E92ZMYYFZ',
  '9SIQT8TOJO',
  'L9ECAV7KIM',
  'LS4PSXUNUM',
  'OLJCESPC7Z'
];

const currencies = ['EUR', 'USD', 'JPY', 'CAD', 'GBP', 'TRY'];

export const options = {
  discardResponseBodies: true,
  scenarios: {
    onlineBoutique: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 60),
      timeUnit: '1s',
      duration: __ENV.DURATION || '6m',
      preAllocatedVUs: 200,
      maxVUs: 2000,
      gracefulStop: '10s'
    }
  }
};

function isSuccessful(response) {
  return response.status >= 200 && response.status < 400;
}

function recordOperation(startTime, responses) {
  const duration = Date.now() - startTime;
  const successful = responses.every(isSuccessful);
  const withinSlo = successful && duration <= 1000;

  successfulOperations.add(successful ? 1 : 0);
  sloOperations.add(withinSlo ? 1 : 0);
  operationSuccessRate.add(successful);
  operationGoodputRate.add(withinSlo);
  operationDuration.add(duration);
}

export default function () {
  offeredOperations.add(1);

  const startTime = Date.now();
  const operation = Math.floor(Math.random() * 19);
  const product = products[Math.floor(Math.random() * products.length)];
  const responses = [];

  if (operation === 0) {
    responses.push(http.get(`${__ENV.TARGET_URL}/`));
    recordOperation(startTime, responses);
    return;
  }

  if (operation < 3) {
    responses.push(http.post(`${__ENV.TARGET_URL}/setCurrency`, {
      currency_code: currencies[Math.floor(Math.random() * currencies.length)]
    }));
    recordOperation(startTime, responses);
    return;
  }

  if (operation < 13) {
    responses.push(http.get(`${__ENV.TARGET_URL}/product/${product}`));
    recordOperation(startTime, responses);
    return;
  }

  if (operation < 15) {
    responses.push(http.get(`${__ENV.TARGET_URL}/product/${product}`));
    responses.push(http.post(`${__ENV.TARGET_URL}/cart`, {
      product_id: product,
      quantity: String(Math.floor(Math.random() * 10) + 1)
    }));
    recordOperation(startTime, responses);
    return;
  }

  if (operation < 18) {
    responses.push(http.get(`${__ENV.TARGET_URL}/cart`));
    recordOperation(startTime, responses);
    return;
  }

  responses.push(http.get(`${__ENV.TARGET_URL}/product/${product}`));
  responses.push(http.post(`${__ENV.TARGET_URL}/cart`, {
    product_id: product,
    quantity: String(Math.floor(Math.random() * 10) + 1)
  }));
  responses.push(http.post(`${__ENV.TARGET_URL}/cart/checkout`, {
    email: `user-${__VU}-${__ITER}@example.com`,
    street_address: '1 Rue de Test',
    zip_code: '75001',
    city: 'Paris',
    state: 'IDF',
    country: 'France',
    credit_card_number: '4111111111111111',
    credit_card_expiration_month: '12',
    credit_card_expiration_year: '2030',
    credit_card_cvv: '123'
  }));

  recordOperation(startTime, responses);
}
