import {
  expect,
  test as base,
} from '@playwright/test';

export { expect };

type HTTPErrorAllowance = {
  pathname: string;
  status: number;
  count: number;
};

type BrowserIssue =
  | { kind: 'console'; text: string; url: string; pathname: string | null; status: number | null }
  | { kind: 'page'; text: string };

const resourceError = /^Failed to load resource: the server responded with a status of (\d{3})(?: \([^)]*\))?$/;

export class BrowserErrorObserver {
  private readonly allowances: HTTPErrorAllowance[] = [];
  private readonly issues: BrowserIssue[] = [];

  allowHTTPError(allowance: HTTPErrorAllowance) {
    this.allowances.push(allowance);
  }

  recordConsole(type: string, text: string, url: string) {
    if (type !== 'error') return;
    const match = text.match(resourceError);
    let pathname: string | null = null;
    try {
      pathname = new URL(url).pathname;
    } catch {
      // An error without a valid source URL cannot match an endpoint allowance.
    }
    this.issues.push({
      kind: 'console',
      text,
      url,
      pathname,
      status: match ? Number.parseInt(match[1], 10) : null,
    });
  }

  recordPageError(error: Error) {
    this.issues.push({ kind: 'page', text: error.message });
  }

  verify() {
    const counts = new Map(this.allowances.map((allowance) => [allowance, 0]));
    const unexpected: BrowserIssue[] = [];
    for (const issue of this.issues) {
      if (issue.kind === 'page') {
        unexpected.push(issue);
        continue;
      }
      const allowance = this.allowances.find((candidate) => (
        candidate.pathname === issue.pathname && candidate.status === issue.status
      ));
      if (!allowance) {
        unexpected.push(issue);
        continue;
      }
      counts.set(allowance, counts.get(allowance)! + 1);
    }

    const wrongCounts = this.allowances.flatMap((allowance) => {
      const actual = counts.get(allowance)!;
      return actual === allowance.count ? [] : [{ ...allowance, actual }];
    });
    if (unexpected.length || wrongCounts.length) {
      throw new Error(`unexpected browser errors: ${JSON.stringify({ unexpected, wrongCounts })}`);
    }
  }
}

type BrowserErrorFixtures = {
  browserErrors: BrowserErrorObserver;
};

export const test = base.extend<BrowserErrorFixtures>({
  browserErrors: [async ({ page }, use) => {
    const observer = new BrowserErrorObserver();
    page.on('console', (message) => {
      observer.recordConsole(message.type(), message.text(), message.location().url);
    });
    page.on('pageerror', (error) => observer.recordPageError(error));
    await use(observer);
    observer.verify();
  }, { auto: true }],
});
