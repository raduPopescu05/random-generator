import test from 'node:test';
import assert from 'node:assert/strict';

const baseUrl = process.env.BASE_URL ?? 'http://localhost:3000';

async function getJson(path) {
    const response = await fetch(`${baseUrl}${path}`);
    const body = await response.json();
    return { response, body };
}

test('the running application exposes healthy endpoints and persists generations', async () => {
    const live = await getJson('/health/live');
    assert.equal(live.response.status, 200);
    assert.equal(live.body.status, 'alive');

    const ready = await getJson('/health/ready');
    assert.equal(ready.response.status, 200);
    assert.equal(ready.body.status, 'ready');

    const number = await getJson('/number');
    assert.equal(number.response.status, 200);
    assert.ok(Number.isInteger(number.body.value));
    assert.ok(number.body.value >= 0 && number.body.value <= 99);

    const letter = await getJson('/letter');
    assert.equal(letter.response.status, 200);
    assert.match(letter.body.value, /^[A-Z]$/);

    const game = await getJson('/rock-paper-scissors');
    assert.equal(game.response.status, 200);
    assert.ok(['rock', 'paper', 'scissors'].includes(game.body.value));

    const history = await getJson('/history?limit=10');
    assert.equal(history.response.status, 200);
    assert.ok(Array.isArray(history.body.generations));
    assert.ok(history.body.generations.length <= 10);
    assert.ok(history.body.generations.some((entry) => entry.value === String(number.body.value)));
});
