# TeamBuddy migration

## Approved scope

Replace the retired Labforge endpoints with TeamBuddy and show native menu metrics.
Keep TokenBoard's identity, bundle identifier, and Micu account storage.
After initially choosing an embedded console, the user clarified that quota must
be visible directly in TokenBoard. Web login now supplies authentication only;
the app reads the new team quota and overview APIs inside the same HTTPS origin.

## Implementation and verification

- [x] Add TeamBuddy website, console, and inference API URLs in `TeamBuddyEndpoints.swift`.
- [x] Add a reusable AppKit window with a persistent WKWebView. Load the real
  console, allow HTTPS navigation on TeamBuddy, open external HTTPS links in the
  browser, and offer reload/browser fallback. Keep credentials in the website.
- [x] Replace Labforge metrics with native TeamBuddy quota, consumption, and
  reset-time rows. Test currency conversion, unlimited quotas and expired login.
  Use a persistent WKWebView for cookie refresh and authenticated reads, with
  access tokens remaining in page JavaScript. Keep console and API-copy actions.
  Remove the app's old login/refresh tasks and preferences; retain the legacy
  core code and storage for compatibility, without invoking its network client.
- [x] Update README to describe the new workflow and its login requirement.
- [x] Run `swift build`, `swift run LabforgeVerify`, `swift run MicuVerify`, and
  `swift run MicuOAuthVerify`. Build `dist/TokenBoard.dmg` and verify its signature.
- [x] Open the built app and check the menu and TeamBuddy console. Report any
  authentication or embedded-browser limitation without claiming a real login.

## Verification evidence

- `swift build`, `LabforgeVerify`, `MicuVerify`, and `MicuOAuthVerify` passed.
- Compiled the production window/controller and native menu views into an isolated
  UI smoke app. Original-account login succeeded, survived process restart, and
  native quota rows displayed live personal/team balances and reset time without
  showing a web window. Unlimited quotas and disabled teams are covered by the
  verifier. Removed temporary account probe files after verification.
- Built and signed `dist/TokenBoard.dmg`; verified the app signature and confirmed
  the release binary does not contain the excluded default password.
- Backed up the previous `/Applications/TokenBoard.app` and installed the verified
  build. The production app uses its own persistent WebKit session and may need
  one initial login; the isolated smoke session is not copied into it.

## Compact metrics and team ranking

- Show personal and team used/limit rows without repeating remaining values.
- `/api/rankings?period=today` returns `rankings is disabled`.
- `/api/team/usage` rejects this member account; do not attempt to bypass it.
- The authorized `/api/team/overview` response includes `member_usage`, up to five
  leaders by current-period consumed quota. Display these in a default-expanded native
  disclosure, with explicit scope and no inferred personal rank beyond that list.
- Verify ordering, tied consumption, name fallback, and absent ranking data with
  `LabforgeVerify`; render the production menu and verify the default-expanded ranking in UI QA.

## Ranking appearance

Restore the previous orange trophy header, lightly tinted rounded card with a
thin border, fixed-width bold rank column, body-size names and monospaced amounts.
Keep all five current-period entries. Default to expanded on each menu opening,
outline the authenticated user by ID, and put both TeamBuddy actions on one row.
UI QA confirmed the live user row is outlined and both actions fit at 360 pt.
The site supports password login but requires Turnstile; password-only account
addition cannot replace the verification step.
