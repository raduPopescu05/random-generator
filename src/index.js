import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { formatDateYmdHis } from './utils/date.js';
import { generateRandomLetter, generateRandomNumber, generateRandomRockPaperScissors } from './utils/random.js';
import { checkDatabase, initializeDatabase, listGenerations, saveGeneration } from './db.js';
import { metrics } from './utils/metrics.js';

const app = express();
const _PORT = 3000;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

console.log('Starting random generator...');

app.use(express.static(path.join(__dirname, 'public')));
app.use(metrics.middleware);
app.get('/metrics', metrics.endpoint);

app.get('/api', (req, res) => {
    res.json({
        appName: "Random generator",
        status: "Up and running!",
        availableEndpoints: [
            {
                url: "/number",
                description: "generate a random number"
            },
            {
                url: "/letter",
                description: "generate a random letter"
            },
            {
                url: "/rock-paper-scissors",
                description: "generate a random rock - papers - scissors option"
            },
            {
                url: "/history",
                description: "list recently generated values"
            }
        ]
    });
});


app.get('/health/live', (req, res) => {
    res.json({ status: 'alive' });
});

app.get('/health/ready', async (req, res) => {
    try {
        await checkDatabase();
        res.json({ status: 'ready' });
    } catch {
        res.status(503).json({ status: 'not ready' });
    }
});

const saveAndRespond = async (res, type, value, description) => {
    try {
        await saveGeneration(type, value);
        res.json({ description, value, timestamp: formatDateYmdHis() });
    } catch {
        res.status(503).json({ error: 'Database is unavailable' });
    }
};

app.get('/number', async (req, res) => {
    const value = generateRandomNumber();
    await saveAndRespond(res, 'number', value, 'Generates a random number');
});

app.get('/letter', async (req, res) => {
    const value = generateRandomLetter();
    await saveAndRespond(res, 'letter', value, 'Generates a random letter');
});

app.get('/rock-paper-scissors', async (req, res) => {
    const value = generateRandomRockPaperScissors();
    await saveAndRespond(res, 'rock-paper-scissors', value, 'Generates a rock - papers - scissors option');
});

app.get('/history', async (req, res) => {
    try {
        const generations = await listGenerations(req.query.limit);
        res.json({ generations });
    } catch {
        res.status(503).json({ error: 'Database is unavailable' });
    }
});

await initializeDatabase();

app.listen(_PORT, () => {
    console.log(`Server running on http://localhost:${_PORT}`);
});
