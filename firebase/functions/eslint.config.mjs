import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['lib/**', 'node_modules/**', '*.config.mts', 'eslint.config.mjs'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['src/**/*.ts', 'test/**/*.ts'],
    rules: {
      'no-console': ['error', { allow: ['warn', 'error'] }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/no-non-null-assertion': 'off',
    },
  },
  {
    // The pure engine and market maker must never depend on Firebase.
    files: ['src/engine/**/*.ts', 'src/market/**/*.ts'],
    rules: {
      'no-restricted-imports': ['error', { patterns: ['firebase-admin*', 'firebase-functions*', 'firebase/*', '**/shared/admin', '**/shared/paths', '**/shared/wallet'] }],
    },
  },
  {
    files: ['test/**/*.ts', 'src/sim/**/*.ts'],
    rules: { 'no-console': 'off' },
  },
);
