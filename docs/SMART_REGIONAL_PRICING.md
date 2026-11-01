# Smart Regional Pricing — Pass 1 API Contracts and Handoff

**Issue:** [#8](https://github.com/hoangbkit/MyApps/issues/8)  
**Target:** `develop` · **Pass:** 1 of 5 · **Mode:** read-only  
**Review date:** 2026-11-01 · **Baseline:** `develop` at implementation time; no live Apple account writes.

## What this pass implements

- Existing App Store Connect JWT/session/Keychain remains the only authentication path. A `URLSession` injection point permits future offline fixture testing. No new backend or credentials store.
- Normalized product discovery: v2 non-consumable IAP, subscription groups, subscriptions, unsupported IAP kinds.
- Lightweight US price summaries, fetched per product on demand; no all-country ladder eager loads.
- Full selected-product read: territory catalog, IAP base territory and manual/automatic schedules, subscription plan availability, public/preserved/future price records, valid US point ladder, partial read issues.
- Bounded four-at-a-time resolution when the API response omits an included price-point resource. Never guess point IDs or treat missing data as free.
- On-demand territory point ladders and standard equalizations, with `Decimal` parsing.
- JSON:API response error details and `Retry-After` context while preserving the existing Xcode Cloud HTTP 404 behavior.
- Pagination follows `links.next` for the **primary resource**; embedded `included` items are not assumed complete.
- A sorted semantic snapshot fingerprint for later stale-review checks. This is an initial read fingerprint, **not** a sufficient write precondition in Pass 4.

No Pricing UI, suggestion engine, mapping bundle, journal, product writes, or live price tests in Pass 1.

## API inventory — Apple documentation checked November 1, 2026

| Purpose | Endpoint | Notes |
| --- | --- | --- |
| IAP discovery | `GET /v1/apps/{appID}/inAppPurchasesV2` | `inAppPurchaseType=NON_CONSUMABLE` only supported for write path |
| Group discovery | `GET /v1/apps/{appID}/subscriptionGroups` | Fetch subscriptions through the group collection |
| Subscription discovery | `GET /v1/subscriptionGroups/{groupID}/subscriptions` | `subscriptionPeriod` is not `planType` |
| Territory catalog | `GET /v1/territories` | Currency supplied by territory attributes |
| IAP schedule | `GET /v2/inAppPurchases/{iapID}/iapPriceSchedule` | Retain configured `baseTerritory`; missing schedule ≠ zero |
| IAP base territory | `GET /v1/inAppPurchasePriceSchedules/{scheduleID}/baseTerritory` | Explicit fallback if schedule omits linked base ID |
| IAP prices | `GET /v1/inAppPurchasePriceSchedules/{scheduleID}/manualPrices` and `/automaticPrices` | Follow all pages, including >50 entries; schedules are separate |
| IAP availability | `GET /v2/inAppPurchases/{iapID}/inAppPurchaseAvailability`; `GET /v1/inAppPurchaseAvailabilities/{availabilityID}/availableTerritories` | Read-only, complete explicit territory collection |
| IAP ladder | `GET /v2/inAppPurchases/{iapID}/pricePoints?filter[territory]=...` | Raw opaque points, max limit 8000 |
| IAP equalization | `GET /v1/inAppPurchasePricePoints/{pointID}/equalizations` | JSON endpoint path implemented; some responses may be CSV |
| Subscription public/preserved/future prices | `GET /v1/subscriptions/{subscriptionID}/prices` | `preserved`, `planType`, `startDate` must not be conflated |
| Subscription plans | `GET /v1/subscriptions/{id}/planAvailabilities`; `GET /v1/subscriptionPlanAvailabilities/{id}/availableTerritories` | Prefer modern plan-specific availability; legacy subscription availability deprecated |
| Subscription ladder | `GET /v1/subscriptions/{id}/pricePoints?filter[territory]=...` | Apple recommends/soon requires territory filter |
| Subscription equalization | `GET /v1/subscriptionPricePoints/{pointID}/equalizations` | Plain equalization is **not** necessarily plan-adjusted |
| Adjusted equalization | `GET /v1/subscriptionPricePoints/{pointID}/adjustedEqualizations` | May return **text/csv**, with plan filters; not implemented until response contract is handled |

Source documents:

- [Apple: List IAPs](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-inapppurchasesv2)
- [Apple: IAP schedule](https://developer.apple.com/documentation/appstoreconnectapi/get-v2-inapppurchases-_id_-iappriceschedule)
- [Apple: IAP manual prices](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-inapppurchasepriceschedules-_id_-manualprices)
- [Apple: IAP automatic prices](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-inapppurchasepriceschedules-_id_-automaticprices)
- [Apple: IAP availability](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-inapppurchaseavailabilities-_id_-availableterritories)
- [Apple: IAP price points](https://developer.apple.com/documentation/appstoreconnectapi/get-v2-inapppurchases-_id_-pricepoints)
- [Apple: Subscription prices](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-prices)
- [Apple: Subscription plan availability](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-planavailabilities)
- [Apple: Subscription points](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-pricepoints)
- [Apple: Adjusted subscription equalizations](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptionpricepoints-_id_-adjustedequalizations)

## Normalized model rules

- `PricingProduct.id` is an App Store Connect resource ID; `productID` is the developer-defined product identifier. Never infer resource ID from an encoded string or product name.
- `PricingTerritory.available == nil` means availability could not be read. It does **not** mean the product is unavailable.
- Currency and Apple price-point amount are independently sourced. Prices missing a point or amount retain nil with an issue, not `0`.
- IAP manual and auto records remain distinct, as do future scheduled records.
- Subscription `preserved=true` is a previous subscriber's price, not a new subscriber's public price. Multiple active billing plan types do not collapse into one summary price.
- `subscriptionPeriod` (weekly/monthly/annual) is independent from billing `planType` (`MONTHLY` / `UPFRONT`); unknown plan values are explicitly flagged.
- Effective public price selection considers all start dates relative to date, plus any end dates. A null start date is **not** the sole definition of current.
- Account scope is a SHA-256 of issuer and key ID, not a persisted signing secret; this does not grant permission to resume any write later.
- For subscription availability, the modern plan-specific endpoint is authoritative. A missing plan configuration remains unknown rather than implicitly inferring support from the deprecated collection.
- `PricingDecimal.parse` accepts strict positive POSIX decimal strings, not floating-point currency.

## Limitations and contracts to finish before generation or writes

1. **Adjusted subscription equalization:** Apple documents `text/csv` with additional upfront point / plan filters. No CSV parser or plan-specific selection exists in Pass 1. For cases requiring adjusted equalizations, **block** generation/submit in a later pass until the exact response and plan identity are implemented. Do not silently use plain equalizations as an equivalent substitute.
2. **IAP / subscription point equalization media types:** Some Apple endpoints may return CSV. The shared JSON decoder detects unsupported media instead of inventing data. Pass 2 must support the media type actually returned for ordinary target products or surface a blocking exception.
3. **Schedule write semantics:** The [IAP schedule POST](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-inapppurchasepriceschedules) requires a base territory. Exact complete-schedule preservation, indirect automatic effects, multiple country price rows, and the date/replace semantics must be verified before Pass 4. No write DTO or POST added now.
4. **Subscription writer:** [Apple's subscription pricing guide](https://developer.apple.com/documentation/appstoreconnectapi/configuring-subscription-prices-across-territories) specifies per-territory `POST /v1/subscriptionPrices`. Precise `preserveCurrentPrice` semantics, date validity, plan variants, and subscriber cohort protections must be rechecked before Pass 5. No writer added now.
5. **Schedule effective windows:** Current read normalization compares ISO date-only strings. Validate inclusivity and how Apple represents open-ended future schedule records against real fixtures before using it to authorize writes.
6. **Availability fallback:** If plan availability is absent or 403, snapshot includes an issue and unknown eligibility. Do not treat all countries as eligible.
7. **Remote verification:** No Apple account API key or live pricing snapshot was used. Actual permissions, less common response shapes, and availability anomalies remain unverified. Existing error handling preserves partial snapshot issues; no mutation is possible.

## Offline fixture verification plan (prepared; **not executed**)

Use an injected `URLSession` (fixture URLProtocol) and fixed response bodies. All fixtures must be redacted, with no JWTs, credentials, or account-derived secrets.

| Case | Response setup | Expected behavior |
| --- | --- | --- |
| IAP discovery | Mixed non-consumable, consumable, non-renewing | Lifetime supported; others labeled unsupported |
| Product pagination | Two pages, duplicate includes, opaque IDs | All primary records collected, no synthetic IDs |
| IAP large schedule | >50 manual entries, multiple automatic pages | All schedule rows returned; maintained separately |
| Price timing | past/current/future and open-ended records | Current selected by effective date, future retained |
| Preserved cohorts | Subscription prices with `preserved=true` | Separated from public prices |
| Plan availability | Standard `UPFRONT` plus `MONTHLY`, missing plan | Plan scopes separated; missing plan is not inferred |
| Missing US reference | No schedule or only preserved US price | Current US unknown; no zero-price guess |
| Limited permission | 403 availability, 200 prices | Partial snapshot issue, unknown eligibility |
| Rate limiting | 429 with `Retry-After` and JSON:API code | Typed error includes status and retry context |
| Missing included point | Related point absent from `included` | Fetch opaque point detail with max four concurrent reads |
| Bad decimal / malformed JSON | Non-parseable amount or response | Nil + issue or structured error; not fabricated amount |
| CSV response | Equalization returns `text/csv` | Explicit unsupported media; never decode as JSON |
| Host safety | Pagination link to third-party host | Reject without sending token |
| No write | Observe all requests in fixture session | Only GET; never POST/PATCH/DELETE |

## Pass 1 handoff

**Completed in code (unverified at runtime):** typed wire/normalized models, read-only endpoint wrappers, US summary, selected snapshot, basic account-scoped in-memory territory cache, point resolution with max-four concurrency, structured transport errors and response media handling, Xcode source membership.

**Not done:** tier data, deterministic generation, country review UI, overrides, drafts, submission, persistence, live pricing writes.

**Verification:** Apple documentation reviewed; source inspected manually. **No Xcode build, tests, CI, fixture execution, or live Apple API calls were run.** An Xcode build and the fixtures above remain necessary to establish compile/runtime correctness. Use `./generate.sh` to regenerate from `project.yml` if the checked-in project drifts.

**Next pass:** mapping, deterministic engine, overrides, versioned local drafts (Pass 2 only, when explicitly requested).
