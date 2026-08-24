---
name: linkedin-profile
description: Read-only access to my LinkedIn profile data via LinkedIn's DMA Member Data Portability API. Use when a task needs my LinkedIn profile, work history (POSITIONS), education, skills, languages, endorsements, or related personal LinkedIn data.
---

# LinkedIn profile (read-only, DMA Member Data Portability API)

This gives an agent read access to my LinkedIn data through LinkedIn's
official **Member Data Portability (Member)** API (the DMA-driven portability
program). It is **read-only**: it can fetch profile/activity data but cannot
post, comment, message, or edit anything. There is no write API in use.

## Token

- Available as the environment variable `$LINKEDIN_API_KEY`.
- Sourced from the `linkedin_api_key` sops secret
  (`modules/home/sops/secrets/secrets.yaml`) and exposed via
  `home.sessionVariables` in `modules/home/sops/default.nix`, gated by
  `my.is_private`.
- It is a 12-month, 3-legged OAuth token with scope
  `r_dma_portability_self_serve`.

If `$LINKEDIN_API_KEY` is unset in the agent environment, the session was
probably started before `home.sessionVariables` were available. Ask the user
to re-login or start a fresh login shell (or re-activate home-manager) before
retrying. Do NOT ask the user to paste the token into chat.

## Recipe

All requests go to `https://api.linkedin.com/rest/memberSnapshotData`.

Required headers:

- `Authorization: Bearer $LINKEDIN_API_KEY`
- `LinkedIn-Version: 202312`  (ONLY this value is accepted)
- `Content-Type: application/json`

Query one domain:

```bash
curl -sS \
  -H "Authorization: Bearer $LINKEDIN_API_KEY" \
  -H "LinkedIn-Version: 202312" \
  -H "Content-Type: application/json" \
  "https://api.linkedin.com/rest/memberSnapshotData?q=criteria&domain=PROFILE"
```

With no `domain` param, the snapshot iterates over every populated domain,
one domain per page (`paging.total` = number of domains). `count`/`start` do
not batch domains; within a single domain, a large `snapshotData` list is
paginated via `start`/`count`.

Response shape: `elements[]` has `snapshotDomain` (enum) and `snapshotData`
(a list of JSON key-value objects). `elements` holds exactly one domain per
page when no `domain` is specified.

## Which domains to fetch

Resume/profile-relevant domains (fetch these for profile questions):
`PROFILE`, `POSITIONS`, `EDUCATION`, `SKILLS`, `LANGUAGES`,
`CERTIFICATIONS`, `HONORS`, `PUBLICATIONS`, `PROJECTS`, `ORGANIZATIONS`,
`COURSES`, `VOLUNTEERING_EXPERIENCES`, `RECOMMENDATIONS`, `ENDORSEMENTS`,
`PROFILE_SUMMARY`, `TEST_SCORES`, `PATENTS`, `CAUSES_YOU_CARE_ABOUT`.

Do NOT fetch these unless the user explicitly asks (sensitive):
`INBOX`, `CONNECTIONS`, `EMAIL_ADDRESSES`, `PHONE_NUMBERS`, `CONTACTS`,
`SECURITY_CHALLENGE_PIPE`, `AD_TARGETING`, `IDENTITY_CREDENTIALS_AND_ASSETS`,
`PREMIUM_NOTES`, `RECEIPTS`, `RECEIPTS_LBP`, `LOGIN`, `SEARCHES`.

## Interpreting failures

- `401` / `invalid_token` -> token expired or revoked. Walk the user through
  the refresh steps below.
- `403 ACCESS_DENIED` on `memberSnapshotData` -> token has the wrong scope,
  or the "Member Data Portability API (Member)" product is not provisioned on
  the app. Not necessarily expired.
- `426 NONEXISTENT_VERSION` -> the `LinkedIn-Version` header must be exactly
  `202312`.
- `404` on a specific `domain` -> that domain simply has no data on the
  profile (normal, not an error).
- Never use `/v2/userinfo` as a liveness check: it always returns 403 with
  this scope. Health check = `memberSnapshotData?q=criteria` (a 200 proves the
  token is valid).

## Token refresh walkthrough (the user will forget how)

If the token is expired/revoked, do NOT attempt any auth/refresh code. There is
no refresh flow wired up -- the token is regenerated manually. Walk the user
through these exact steps, one at a time:

1. Go to the LinkedIn Developer Portal: "Docs and tools" -> "OAuth Token
   Tools" -> "Create token".
2. Select the app that is provisioned with the **Member Data Portability API
   (Member)** product.
3. Choose scope **`r_dma_portability_self_serve`** and click
   "Request access token".
4. LinkedIn redirects to a login + consent screen -> the user signs in and
   clicks "Allow".
5. Copy the generated access token.
6. Update the secret with `sops modules/home/sops/secrets/secrets.yaml` and
   set the `linkedin_api_key` value to the new token.
7. Re-activate home-manager (`home-manager switch`) and start a fresh login
   shell so `$LINKEDIN_API_KEY` is re-read.
8. Verify with the `PROFILE` curl above; a 200 confirms success.

## References (check here first if something breaks / the API changes)

- Getting started + token generation:
  <https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/member-data-portability-member>
- Member Snapshot API (endpoint, headers, version `202312`, schema, pagination):
  <https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/shared/member-snapshot-api?view=li-dma-data-portability-2026-05&tabs=http>
- Snapshot domain list (all domains, case-sensitive):
  <https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/shared/snapshot-domain?view=li-dma-data-portability-2026-05>
- Member Changelog API (forward-looking activity, 28-day window, only if ever needed):
  <https://learn.microsoft.com/en-us/linkedin/dma/member-data-portability/shared/member-changelog-api?view=li-dma-data-portability-2026-05>
- Member portability help article (eligibility: EU/EEA/CH):
  <https://www.linkedin.com/help/linkedin/answer/a6214075>
- Portability API terms:
  <https://www.linkedin.com/legal/l/portability-api-terms>
