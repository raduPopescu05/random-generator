import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { once } from 'node:events';
import { createMetrics } from '../utils/metrics.js';

test('HTTP metrics record normalized routes, errors and exclude operational/static traffic', async () => {
    const metrics = createMetrics({ defaults: false });
    const app = express();
    app.use(express.static('public'));
    app.use(metrics.middleware);
    app.get('/metrics', metrics.endpoint);
    app.get('/health/ready', (req, res) => res.sendStatus(200));
    app.get('/health/live', (req, res) => res.sendStatus(200));
    app.get('/number', (req, res) => res.sendStatus(200));
    app.get('/history', (req, res) => res.sendStatus(503));
    const server = app.listen(0, '127.0.0.1');
    await once(server, 'listening');
    const url = `http://127.0.0.1:${server.address().port}`;
    try {
        for (const path of ['/', '/health/ready', '/health/live', '/metrics',
            '/number?secret=not-a-label', '/history', '/unknown/123', '/unknown/456']) {
            const response = await fetch(url + path);
            await response.text();
        }
        const response = await fetch(url + '/metrics');
        assert.match(response.headers.get('content-type'), /text\/plain|application\/openmetrics-text/);
        const text = await response.text();
        const samples = (await metrics.registry.getSingleMetric('http_requests_total').get()).values;
        assert.equal(samples.reduce((total, sample) => total + sample.value, 0), 4);
        assert.equal(samples.find(sample => sample.labels.route === 'unmatched').value, 2);
        assert.equal(samples.find(sample => sample.labels.route === '/history').labels.status, '503');
        assert.doesNotMatch(text, /not-a-label|unknown\/123|health\/|route="\/metrics"/);
        assert.match(text, /http_request_duration_seconds_count/);
    } finally {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
    }
});

test('database instrumentation preserves results and errors and records both outcomes', async () => {
    const metrics = createMetrics({ defaults: false });
    const result = { value: 42 };
    assert.equal(await metrics.measureDatabase('list_generations', async () => result), result);
    const error = new Error('database unavailable');
    await assert.rejects(metrics.measureDatabase('insert_generation', async () => { throw error; }), e => e === error);
    const values = (await metrics.registry.getSingleMetric('database_operations_total').get()).values;
    assert.equal(values.find(v => v.labels.operation === 'insert_generation' && v.labels.outcome === 'failure').value, 1);
    assert.equal(values.find(v => v.labels.operation === 'list_generations' && v.labels.outcome === 'success').value, 1);
    const histogram = (await metrics.registry.getSingleMetric('database_operation_duration_seconds').get()).values;
    assert.equal(histogram.filter(v => v.metricName.endsWith('_count')).reduce((sum, v) => sum + v.value, 0), 2);
});

test('generation types and database operations cannot create arbitrary labels', async () => {
    const metrics = createMetrics({ defaults: false });
    metrics.recordGeneration('number');
    assert.throws(() => metrics.recordGeneration('arbitrary-id'));
    await assert.rejects(metrics.measureDatabase('raw SQL', async () => {}));
    const values = (await metrics.registry.getSingleMetric('generations_total').get()).values;
    assert.equal(values.length, 3);
    assert.equal(values.find(v => v.labels.type === 'number').value, 1);
    assert.equal(values.find(v => v.labels.type === 'letter').value, 0);
});

test('default registry exposes Node runtime metrics', async () => {
    const metrics = createMetrics();
    const text = await metrics.registry.metrics();
    assert.match(text, /process_start_time_seconds/);
    assert.match(text, /nodejs_heap_size_used_bytes/);
    assert.match(text, /nodejs_eventloop_lag/);
});
