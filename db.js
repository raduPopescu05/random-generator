import mysql from 'mysql2/promise';
import { metrics } from './utils/metrics.js';

const pool = mysql.createPool({
    host: process.env.DB_HOST ?? '127.0.0.1',
    port: Number(process.env.DB_PORT ?? 3306),
    database: process.env.DB_NAME ?? 'random_generator',
    user: process.env.DB_USER ?? 'random_app',
    password: process.env.DB_PASSWORD ?? 'random_password',
    waitForConnections: true,
    connectionLimit: 5,
    queueLimit: 0
});

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

export async function initializeDatabase({ retries = 30, delayMs = 2000 } = {}) {
    const schema = `
        CREATE TABLE IF NOT EXISTS generations (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            type VARCHAR(32) NOT NULL,
            value VARCHAR(255) NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            INDEX idx_generations_created_at (created_at)
        ) ENGINE=InnoDB;
    `;

    for (let attempt = 1; attempt <= retries; attempt += 1) {
        try {
            await pool.query(schema);
            console.log('Database schema is ready.');
            return;
        } catch (error) {
            if (attempt === retries) throw error;
            console.log(`Database is not ready (attempt ${attempt}/${retries}); retrying...`);
            await sleep(delayMs);
        }
    }
}

export async function checkDatabase() {
    await metrics.measureDatabase('readiness', () => pool.query('SELECT 1'));
}

export async function saveGeneration(type, value) {
    await metrics.measureDatabase('insert_generation', () => pool.execute(
        'INSERT INTO generations (type, value) VALUES (?, ?)',
        [type, String(value)]
    ));
    metrics.recordGeneration(type);
}

export async function listGenerations(limit = 20) {
    const safeLimit = Math.min(Math.max(Number.parseInt(limit, 10) || 20, 1), 100);
    const [rows] = await metrics.measureDatabase('list_generations', () => pool.query(
        `SELECT id, type, value, created_at
         FROM generations
         ORDER BY id DESC
         LIMIT ${safeLimit}`
    ));
    return rows;
}
