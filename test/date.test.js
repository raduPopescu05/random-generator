import test from 'node:test';
import assert from 'node:assert/strict';
import { formatDateYmdHis } from '../src/utils/date.js';

test('formats a date as YYYY-MM-DD HH:mm:ss', () => {
    const date = new Date(2026, 8, 14, 5, 6, 7);
    assert.equal(formatDateYmdHis(date), '2026-09-14 05:06:07');
});

test('pads single digit date and time values', () => {
    const date = new Date(2026, 0, 2, 3, 4, 5);
    assert.equal(formatDateYmdHis(date), '2026-01-02 03:04:05');
});
