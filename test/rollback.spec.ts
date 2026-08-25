import { expect, test } from './fixtures/real-dex';
import {
  authorizationPath,
  baseURL,
  readTOTPSecret,
  submitPassword,
  submitTOTP,
  totp,
} from './fixtures/real-dex';

test.describe('embedded upstream frontend rollback', () => {
  test('preserves login, consent, TOTP, WebAuthn, home, and logout flows', async ({
    page,
    browserErrors,
    createVirtualAuthenticator,
  }) => {
    test.setTimeout(45_000);

    await page.goto(authorizationPath({ scopes: ['openid', 'profile', 'email'] }));
    await expect(page.getByRole('link', { name: 'Log in with Email' })).toBeVisible();
    await page.getByRole('link', { name: 'Log in with Email' }).click();
    await expect(page.locator('form')).toHaveAttribute('method', 'post');
    await expect(page.getByLabel('Email Address')).toBeFocused();

    await submitPassword(page, 'rollback@example.invalid');
    await expect(page.getByRole('heading', { name: 'Two-factor authentication' })).toBeVisible();
    await expect(page.getByRole('img', { name: 'QR code' })).toHaveAttribute('src', /^data:image\/png;base64,/);
    await expect(page.getByLabel('One-time code')).toBeFocused();

    const secret = readTOTPSecret('00000000-0000-4000-8000-000000000008');
    await submitTOTP(page, totp(secret, -1));
    await expect(page.getByRole('heading', { name: 'Register security key' })).toBeVisible();
    await expect(page.locator('#webauthn-btn')).toHaveAttribute('type', 'button');
    await createVirtualAuthenticator();
    await Promise.all([
      page.waitForURL(/\/approval\?/),
      page.getByRole('button', { name: 'Register Security Key' }).click(),
    ]);

    await expect(page.getByRole('heading', { name: 'Grant Access' })).toBeVisible();
    await expect(page.locator('form')).toHaveCount(2);
    browserErrors.allowHTTPError({ pathname: '/client/callback', status: 404, count: 1 });
    await page.getByRole('button', { name: 'Grant Access' }).click();
    await expect(page).toHaveURL(/\/client\/callback\?/);

    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'rollback-user' })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Log out' })).toHaveAttribute('href', new URL('/logout', baseURL()).href);

    await page.goto('/logout');
    await expect(page.getByRole('heading', { name: 'Logging Out' })).toBeVisible();
    await page.getByRole('button', { name: 'Log Out' }).click();
    await expect(page.getByRole('heading', { name: 'Logged Out' })).toBeVisible();
  });
});
