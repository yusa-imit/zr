import { describe, it, expect } from 'vitest';
import { greet, add } from './index.js';

describe('greet', () => {
  it('should greet with the given name', () => {
    expect(greet('Alice')).toBe('Hello, Alice!');
  });

  it('should work with different names', () => {
    expect(greet('Bob')).toBe('Hello, Bob!');
  });
});

describe('add', () => {
  it('should add two positive numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  it('should add negative numbers', () => {
    expect(add(-1, -2)).toBe(-3);
  });

  it('should handle zero', () => {
    expect(add(0, 5)).toBe(5);
    expect(add(5, 0)).toBe(5);
  });
});
