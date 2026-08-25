import { execFileSync } from 'node:child_process';
import { createHmac } from 'node:crypto';
import assert from 'node:assert/strict';
import {
  type CDPSession,
  type Page,
} from '@playwright/test';
import { expect, test as observedTest } from './browser-errors';

export { expect };

type AuthorizationOptions = {
  scopes?: string[];
  redirectURI?: string;
  prompt?: string;
};

export function baseURL() {
  const value = process.env.DEX_TEST_BASE_URL;
  assert.ok(value, 'DEX_TEST_BASE_URL is required; run scripts/test-image.sh');
  return value;
}

export function authorizationPath(options: AuthorizationOptions = {}) {
  const query = new URLSearchParams({
    client_id: 'araihu-test',
    redirect_uri: options.redirectURI ?? new URL('/client/callback', baseURL()).href,
    response_type: 'code',
    scope: (options.scopes ?? ['openid']).join(' '),
  });
  if (options.prompt) query.set('prompt', options.prompt);
  return `/auth?${query}`;
}

export async function openPassword(page: Page, path = authorizationPath()) {
  await page.goto(path);
  await page.getByRole('link', { name: 'Log in with Email' }).click();
}

export async function submitPassword(page: Page, email: string, password = 'password') {
  await page.getByLabel('Email Address').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Login' }).click();
}

export function readMFASecrets(userID: string) {
  const database = process.env.DEX_TEST_DB;
  assert.ok(database, 'DEX_TEST_DB is required; run scripts/test-image.sh');
  const sql = `select cast(mfa_secrets as text) from user_identity where user_id = '${userID}' and connector_id = 'local';`;
  const output = execFileSync('/usr/bin/sqlite3', ['-readonly', '-cmd', '.timeout 5000', database, sql], {
    encoding: 'utf8',
  }).trim();
  assert.ok(output, `MFA identity not found for ${userID}`);
  return JSON.parse(output) as Record<string, { secret: string }>;
}

export function readTOTPSecret(userID: string) {
  const secret = readMFASecrets(userID)['totp-1']?.secret;
  assert.ok(secret, `TOTP enrollment secret missing for ${userID}`);
  return secret;
}

function decodeBase32(value: string) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = 0;
  let accumulator = 0;
  const output: number[] = [];
  for (const character of value.toUpperCase().replaceAll('=', '')) {
    const digit = alphabet.indexOf(character);
    assert.notEqual(digit, -1, `invalid base32 character: ${character}`);
    accumulator = (accumulator << 5) | digit;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      output.push((accumulator >>> bits) & 0xff);
    }
  }
  return Buffer.from(output);
}

export function totp(secretURL: string, offset = 0) {
  const secret = new URL(secretURL).searchParams.get('secret');
  assert.ok(secret, 'TOTP URL has no secret');
  const counter = BigInt(Math.floor(Date.now() / 30_000) + offset);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(counter);
  const digest = createHmac('sha1', decodeBase32(secret)).update(message).digest();
  const index = digest[digest.length - 1] & 0x0f;
  const value = (digest.readUInt32BE(index) & 0x7fffffff) % 1_000_000;
  return value.toString().padStart(6, '0');
}

export function definitelyInvalidTOTP(secretURL: string) {
  const valid = new Set([-1, 0, 1].map((offset) => totp(secretURL, offset)));
  for (let candidate = 0; candidate < 10; candidate += 1) {
    const code = candidate.toString().padStart(6, '0');
    if (!valid.has(code)) return code;
  }
  throw new Error('could not choose invalid TOTP code');
}

export async function submitTOTP(page: Page, code: string) {
  await page.getByLabel('One-time code').fill(code);
  await page.getByRole('button', { name: 'Verify' }).click();
}

export type VirtualAuthenticator = {
  session: CDPSession;
  authenticatorId: string;
  setPresence(enabled: boolean): Promise<void>;
};

export type CreateVirtualAuthenticator = (
  automaticPresenceSimulation?: boolean,
) => Promise<VirtualAuthenticator>;

type RealDexFixtures = {
  createVirtualAuthenticator: CreateVirtualAuthenticator;
};

export const test = observedTest.extend<RealDexFixtures>({
  createVirtualAuthenticator: async ({ page }, use) => {
    const authenticators: VirtualAuthenticator[] = [];
    await use(async (automaticPresenceSimulation = true) => {
      const session = await page.context().newCDPSession(page);
      await session.send('WebAuthn.enable');
      const { authenticatorId } = await session.send('WebAuthn.addVirtualAuthenticator', {
        options: {
          protocol: 'ctap2',
          transport: 'usb',
          hasResidentKey: true,
          hasUserVerification: true,
          isUserVerified: true,
          automaticPresenceSimulation,
        },
      });
      const authenticator: VirtualAuthenticator = {
        session,
        authenticatorId,
        async setPresence(enabled) {
          await session.send('WebAuthn.setAutomaticPresenceSimulation', { authenticatorId, enabled });
        },
      };
      authenticators.push(authenticator);
      return authenticator;
    });
    for (const { session, authenticatorId } of authenticators.reverse()) {
      await session.send('WebAuthn.removeVirtualAuthenticator', { authenticatorId }).catch(() => {});
      await session.send('WebAuthn.disable').catch(() => {});
      await session.detach().catch(() => {});
    }
  },
});
