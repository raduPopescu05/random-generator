import test from 'node:test';
import assert from 'node:assert/strict';
import {
    generateRandomLetter,
    generateRandomNumber,
    generateRandomRockPaperScissors
} from '../utils/random.js';

test('random number is always between 0 and 99', () => {
    for (let attempt = 0; attempt < 1000; attempt += 1) {
        const value = generateRandomNumber();
        assert.ok(Number.isInteger(value));
        assert.ok(value >= 0 && value <= 99);
    }
});

test('random number handles both boundaries', () => {
    const originalRandom = Math.random;
    try {
        Math.random = () => 0;
        assert.equal(generateRandomNumber(), 0);
        Math.random = () => 0.999999;
        assert.equal(generateRandomNumber(), 99);
    } finally {
        Math.random = originalRandom;
    }
});

test('random letter is an uppercase letter from A to Z', () => {
    const originalRandom = Math.random;
    try {
        Math.random = () => 0;
        assert.equal(generateRandomLetter(), 'A');
        Math.random = () => 0.999999;
        assert.equal(generateRandomLetter(), 'T');
    } finally {
        Math.random = originalRandom;
    }
});

test('rock paper scissors returns an allowed value', () => {
    const allowedValues = new Set(['rock', 'paper', 'scissors']);
    for (let attempt = 0; attempt < 1000; attempt += 1) {
        assert.ok(allowedValues.has(generateRandomRockPaperScissors()));
    }
});

test('rock paper scissors handles all three boundaries', () => {
    const originalRandom = Math.random;
    try {
        Math.random = () => 0;
        assert.equal(generateRandomRockPaperScissors(), 'rock');
        Math.random = () => 0.34;
        assert.equal(generateRandomRockPaperScissors(), 'paper');
        Math.random = () => 0.999999;
        assert.equal(generateRandomRockPaperScissors(), 'scissors');
    } finally {
        Math.random = originalRandom;
    }
});
