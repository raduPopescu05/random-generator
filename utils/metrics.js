import { Registry, Counter, Histogram, collectDefaultMetrics } from '@prometheus-io/client';

const routes = new Set(['/api', '/number', '/letter', '/rock-paper-scissors', '/history']);
const excluded = new Set(['/health/live', '/health/ready', '/metrics']);
const methods = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']);
const operations = new Set(['readiness', 'insert_generation', 'list_generations']);
const generationTypes = new Set(['number', 'letter', 'rock-paper-scissors']);
const buckets = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];

export function createMetrics({ defaults = true } = {}) {
    const registry = new Registry();
    if (defaults) collectDefaultMetrics({ register: registry });
    const counter = (name, help, labelNames) =>
        new Counter({ name, help, labelNames, registers: [registry] });
    const histogram = (name, help, labelNames) =>
        new Histogram({ name, help, labelNames, buckets, registers: [registry] });
    const requests = counter('http_requests_total', 'Completed API requests.', ['method', 'route', 'status']);
    const duration = histogram('http_request_duration_seconds', 'API response duration.', ['method', 'route', 'status']);
    const generations = counter('generations_total', 'Successfully persisted generations.', ['type']);
    const database = counter('database_operations_total', 'Completed database operations.', ['operation', 'outcome']);
    const databaseDuration = histogram('database_operation_duration_seconds', 'Database operation duration, including pool wait.', ['operation', 'outcome']);
    for (const type of generationTypes) generations.inc({ type }, 0);
    for (const operation of operations) {
        for (const outcome of ['success', 'failure']) database.inc({ operation, outcome }, 0);
    }
    // Install after express.static: successfully served static files never reach this middleware.
    function middleware(req, res, next) {
        if (excluded.has(req.path.toLowerCase().replace(/\/$/, ''))) return next();
        const start = process.hrtime.bigint();
        res.once('finish', () => {
            const route = routes.has(req.route?.path) ? req.route.path : 'unmatched';
            const labels = {
                method: methods.has(req.method) ? req.method : 'OTHER',
                route,
                status: String(res.statusCode)
            };
            requests.inc(labels);
            duration.observe(labels, Number(process.hrtime.bigint() - start) / 1e9);
        });
        next();
    }
    async function measureDatabase(operation, action) {
        if (!operations.has(operation)) throw new Error('Unknown database metric operation');
        const end = databaseDuration.startTimer({ operation });
        let outcome = 'success';
        try {
            return await action();
        } catch (error) {
            outcome = 'failure';
            throw error;
        } finally {
            database.inc({ operation, outcome });
            end({ outcome });
        }
    }
    function recordGeneration(type) {
        if (!generationTypes.has(type)) throw new Error('Unknown generation metric type');
        generations.inc({ type });
    }
    async function endpoint(req, res) {
        res.set('Content-Type', registry.contentType);
        res.end(await registry.metrics());
    }
    return { registry, middleware, endpoint, measureDatabase, recordGeneration };
}

export const metrics = createMetrics();
