// Prototype bug-report relay (Cloudflare Worker).
//
// M195 tried to send bug bundles straight from the iPad to GitHub and
// reverted it: nobody writes to a GitHub repo anonymously (Gists lost
// anonymous writes in 2018; API, Push and Releases all authenticate), and a
// repo token sitting in a shipped IPA was rightly rejected as a plaintext
// credential on a tablet. M285 revisits it with the token moved OFF the
// device entirely — this Worker is the only thing that ever holds
// GITHUB_TOKEN. The app calls this URL with no credential of its own.
//
// What one request does:
//   1. checks a shared-secret header (an ABUSE THROTTLE, not a security
//      boundary — see relay/README.md for why that split is fine here)
//   2. commits the uploaded zip to a dedicated branch via the Contents API
//   3. files a GitHub issue linking to it, so a report is something an AI
//      (or a person) can find and act on without anyone forwarding a file
//   4. hands the app back the issue URL to show in the result dialog
//
// Deliberately never touches the default branch and never returns or logs
// GITHUB_TOKEN.

const MAX_BUNDLE_BYTES = 25 * 1024 * 1024;

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') {
      return json({ error: 'POST only' }, 405);
    }
    const url = new URL(request.url);
    if (url.pathname !== '/report') {
      return json({ error: 'not found' }, 404);
    }

    if (env.SHARED_SECRET) {
      const got = request.headers.get('x-bug-relay-secret') ?? '';
      if (!timingSafeEqual(got, env.SHARED_SECRET)) {
        return json({ error: 'bad secret' }, 401);
      }
    }

    let form;
    try {
      form = await request.formData();
    } catch (e) {
      return json({ error: `bad form data: ${e}` }, 400);
    }

    const stem = sanitizeStem(String(form.get('stem') ?? ''));
    const description = String(form.get('description') ?? '');
    const file = form.get('bundle');
    if (!(file instanceof File)) {
      return json({ error: 'missing "bundle" file field' }, 400);
    }
    if (file.size > MAX_BUNDLE_BYTES) {
      return json({ error: `bundle too large: ${file.size} bytes` }, 413);
    }

    const owner = env.REPO_OWNER;
    const repo = env.REPO_NAME;
    const branch = env.REPORT_BRANCH || 'bug-reports';
    const gh = (path, init) => fetch(`https://api.github.com${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: 'application/vnd.github+json',
        'User-Agent': 'ipadprocad-bug-relay',
        ...(init?.headers ?? {}),
      },
    });

    try {
      await ensureBranch(gh, owner, repo, branch);

      const path = `bugreports/${stem}.zip`;
      const bytes = new Uint8Array(await file.arrayBuffer());
      const put = await gh(`/repos/${owner}/${repo}/contents/${path}`, {
        method: 'PUT',
        body: JSON.stringify({
          message: `bug report ${stem}`,
          content: base64(bytes),
          branch,
        }),
      });
      if (!put.ok) {
        return json(
          { error: `github contents: ${put.status} ${await put.text()}` },
          502,
        );
      }

      const fileUrl = `https://github.com/${owner}/${repo}/blob/${branch}/${path}`;
      const rawUrl =
        `https://raw.githubusercontent.com/${owner}/${repo}/${branch}/${path}`;
      const firstLine =
        description.split('\n').find((l) => l.trim().length > 0);
      const title = (firstLine || `bug report ${stem}`).slice(0, 120);
      const body = [
        description.trim() || '_(no description given)_',
        '',
        `Bundle: ${fileUrl}`,
        `Raw zip: ${rawUrl}`,
      ].join('\n');

      const issueRes = await gh(`/repos/${owner}/${repo}/issues`, {
        method: 'POST',
        body: JSON.stringify({
          title: `Bug report: ${title}`,
          body,
          labels: env.ISSUE_LABEL ? [env.ISSUE_LABEL] : undefined,
        }),
      });
      if (!issueRes.ok) {
        // The bundle is already committed even without an issue — hand back
        // the file URL so the report is not lost.
        return json(
          {
            error: `github issues: ${issueRes.status} ${await issueRes.text()}`,
            fileUrl,
          },
          502,
        );
      }
      const issue = await issueRes.json();
      return json({ ok: true, issueUrl: issue.html_url, fileUrl });
    } catch (e) {
      return json({ error: `${e}` }, 500);
    }
  },
};

async function ensureBranch(gh, owner, repo, branch) {
  const check = await gh(`/repos/${owner}/${repo}/git/ref/heads/${branch}`);
  if (check.ok) return;

  const repoRes = await gh(`/repos/${owner}/${repo}`);
  if (!repoRes.ok) {
    throw new Error(
      `could not read repo ${owner}/${repo}: ${repoRes.status} ${await repoRes.text()}`,
    );
  }
  const repoJson = await repoRes.json();
  const base = repoJson.default_branch;

  const baseRef = await gh(`/repos/${owner}/${repo}/git/ref/heads/${base}`);
  if (!baseRef.ok) {
    throw new Error(
      `could not read ref heads/${base}: ${baseRef.status} ${await baseRef.text()}`,
    );
  }
  const baseJson = await baseRef.json();

  const createRes = await gh(`/repos/${owner}/${repo}/git/refs`, {
    method: 'POST',
    body: JSON.stringify({
      ref: `refs/heads/${branch}`,
      sha: baseJson.object.sha,
    }),
  });
  if (!createRes.ok) {
    throw new Error(
      `could not create branch ${branch}: ${createRes.status} ${await createRes.text()}`,
    );
  }
}

function sanitizeStem(s) {
  const cleaned = s.replace(/[^A-Za-z0-9._-]/g, '_');
  return cleaned || `report-${Date.now()}`;
}

function base64(bytes) {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

// Not constant-time in the length comparison — the header is an abuse
// throttle, not a credential, so leaking its length costs nothing worth
// guarding (see relay/README.md).
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
