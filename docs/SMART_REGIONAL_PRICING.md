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


---

## Pass 2 — Bundled mapping, deterministic suggestions, and protected drafts

**Implemented on the same PR branch:** `feature/smart-regional-pricing-pass1`. This section supersedes the old "Next pass" handoff above; Pass 3 remains future work.

### Country mapping: sources and coverage

Bundled `MyApps/Resources/Pricing/country-tiers-v1.json`, copied into the app target's resources phase via both XcodeGen and the checked-in Xcode project. The loader validates unique ISO-like opaque territory keys, tiers 1–5, nonempty provenance, the USA tier-1 anchor, and internally consistent high-income PPP comparisons.

- Version: `2026-11-01.v1`; rule: `worldbank-fy2027-gdp-ppp-2024-80pct-v1`.
- Income source: [World Bank FY2027 classification](https://datahelpdesk.worldbank.org/knowledgebase/articles/906519-world-bank-country-and-lending-groups), 2025 Atlas-method GNI bands, accessed 2026-11-01.
- Same-year high-income PPP source: 2024 World Bank WDI values [reposted by Worldometer](https://www.worldometers.info/gdp/gdp-per-capita/?metric=ppp&region=worldwide&source=wb&year=2024). The US anchor used is **85,810 current international dollars (2024)**. Each observed entry stores its actual PPP value, anchor and year. **This mirror has not been independently crosschecked against the live World Bank API.** Its values must not be described as household disposable income or app willingness to pay.
- Current Apple territory IDs must still be checked against `GET /v1/territories`. Apple's [TerritoryCode](https://developer.apple.com/documentation/appstoreconnectapi/territorycode) documentation provides the code convention; no authenticated account or live Apple territory list was available at build time.
- Scope of static bundle: **251 distinct ISO-style entries** (superset, not a claim that Apple currently sells in 251 markets).
  - Tier 1: 25 entries, including USA; tier 2: 63; tier 3: 59; tier 4: 47; tier 5: 25.
  - **32 entries remain unclassified or legacy**, explicitly marked `needsReview`. For them the engine uses Apple's full reference at multiplier **1.00** and displays an unverified-mapping warning instead of inventing a discounted tier.
  - High-income territories with no *established same-year PPP observation in the bundled source* are provisionally tier 2, with the missing-observation provenance. Guernsey/Jersey are explicitly crosswalked from the World Bank's "Channel Islands" high-income group, not guessed from currency.
  - Additional Apple codes absent from the bundle receive the same visible Apple-reference/1.00 fallback; if their equalized reference is missing too, the row blocks rather than fabricating a price.
- The mapping includes unavailable or historical ISO3 territories for defensive coverage. **Mapping coverage against actual current Apple storefronts is not verified until a real authorized read returns the territory set.** No runtime World Bank requests are made.

Preset multipliers: tier 1 **1.00**, tier 2 **0.85**, tier 3 **0.65**, tier 4 **0.45**, tier 5 **0.30**. They are MyApps business heuristics, not recommendations endorsed by the World Bank. Global multiplier editing is not part of this pass.

### Implementation details

- `RegionalPricingModels.swift`: normalized, Codable/Sendable preset, mapping/provenance, proposal, rows, overrides, warning/diff/status, excluded territories, subscriber-policy acknowledgment, and per-product sibling advisory contracts.
- `RegionalPricingService.loadReferenceSet`: loads reference equalizations and country price-point ladders on demand for one product with **four concurrent reads maximum**. Fetches actual proposed base-territory equalizations for non-US IAP base countries rather than conflating US reference with Apple's configured base. A missing ladder blocks that territory; a missing required global equalization blocks included rows. Unknown commitment/other subscription plans block standard pricing generation.
- `RegionalPricingEngine.generate`: a **pure** function. Validates the selected US point belongs to the selected product and date is valid. Each row independently computes `target = Decimal(Apple equalized local customer price) × tier factor` and selects a valid point with the smallest absolute local-price error. Ties choose the lower amount; duplicate amounts choose the Apple reference ID, then lowest opaque ID. USA retains its exact selected point. Out-of-range targets clamp to the closest valid point with a visible warning. No FX conversion, separate VAT adjustment, arbitrary price amounts or constructed Apple point IDs.
- Public price is resolved relative to selected date, independent of preserved subscription cohorts. Maintenance-mode changes, future schedule conflicts, missing price/currency, and excluded automatically affected IAP countries are flagged. Existing manual IAP countries stay manual unless a separately reviewed reset-to-Apple feature is implemented. A 1.00 fallback does not imply validated PPP.
- `RegionalPricingEngine.validatedOverride` permits only matching Apple point/product/territory/plan/currency. Regenerating revalidates previously saved overrides; invalid ones remain visible with blockers rather than being silently deleted. Target values always derive from original Apple reference and **never** from a previous discounted proposal.
- Fingerprints hash sorted semantic row/reference/preset/date/maintenance/override/subscriber-policy state, not array delivery order or timestamps. The existing Pass 1 snapshot fingerprint remains a preliminary read snapshot rather than a write-safe CAS guarantee.
- `PricingDraftStore`: `Application Support/RegionalPricingDrafts`, hashed account/product filenames, `Codable` version 1, atomic protected writes, excluded from device backup. No SwiftData/CloudKit schema change. Credential-scope mismatches are rejected; restored drafts **always require a fresh remote review** and never auto-submit. This is not the later Pass 4 operation journal.
- Advisory comparisons require an *explicit verified service-level identity* plus subscription group/currency. Only when these agree can a yearly price >12× monthly become a warning. Comparing lifetime price to recurring purchases is informational only.

### Worked fixtures — invented numbers, NOT live Apple prices

| Scenario | Reference and allowed points | Expected deterministic result |
| --- | --- | --- |
| Tier 3 | Reference ¥620; 65% target ¥403; valid points ¥400/¥410 | Choose ¥400 |
| Tier 4 repeat | Reference 10.00; factor 0.45; point ladder 4.49/4.59 | Choose 4.49 twice, never discount 4.49 again |
| Equidistant | Target 5.00; allowed 4.00 and 6.00 | Choose 4.00 |
| Duplicate amount | Two valid 3.99 points | Reference ID wins if present, else lowest opaque ID |
| Zero-decimal currency | Ref 120 units; tier 4 target 54; points 50 and 60 | Choose 50 |
| Below minimum | Target 0.20, smallest valid 0.49 | Choose 0.49 with clamped warning |
| Missing equalization | No confirmed Apple point for territory | Row blocked; no guessed FX price |
| Unknown storefront | New code absent from bundled list | 1.00 factor + warning; still needs valid Apple points |
| Invalid saved override | Old point removed from Apple's ladder | Preserve override visually; block selected row |
| IAP non-US base | US chosen, configured base DEU | Calculate configured-base proposal, fetch its equalizations; block if effects unknown |
| Preserved subscription | Public price 4.99; preserved subscriber price 3.99 | Public baseline 4.99, preserved price remains separate |
| Future schedule | Upcoming Apple row after proposal date | Explicit schedule-conflict blocker |

### Remaining Pass 2 verification and limitations

- **No Xcode toolchain available for an iOS build in this environment. No unit tests, fixture execution, CI dispatch, live Apple reads, or pricing writes were performed.** Compile/runtime correctness has not been established; the first permitted build must validate strict Swift 6 concurrency, XcodeGen project membership, and resource-bundle lookup.
- No authenticated Apple read was available to confirm all API response variants, territory set, price ladders, equalization media types, or subscription plan fields. CSV/adjusted equalizations are not parsed; affected flows intentionally block instead of using unverified fallback amounts.
- A refreshed Apple snapshot and valid ladders are mandatory before the review can be trusted. The Pass 4 write planner must separately verify full schedule semantics, subscriber treatment, indirect base-price effects and Apple state immediately before dispatch.
- **Not implemented in this pass:** pricing screens, a main-actor review view model, submissions, write journal, resume/reconciliation, subscription cohort writes, analytics or backend.

**Handoff for Pass 3:** use the above pure models/engine and the service's `loadReferenceSet` to implement only the read-only Generate/Review experience, override picker, and stale-review UX in the existing app-detail dropdown. Do not enable Submit before Pass 4/5.


---

## Pass 3 — Read-only Pricing UI, generate/review flow

**Status:** Source implementation on existing PR #9. **No Apple writes, tests, CI, build, or device run performed.** Compile/UI verification remains outstanding.

### Screen flow and files

1. **App Store app detail title menu:** `AppStoreAppDetailView` now has **Info / Xcode Cloud / Pricing**, including the accessibility hint. Pricing does not preload when viewing other sections. Existing Info/Xcode Cloud logic remains unchanged.
2. **`AppStorePricingView`:** Product discovery grouped by lifetime IAP and subscription group. Native form/list patterns, a non-sticky inline filter, product name/ID/duration and current US price where verified, plus an explicit unknown/error value. Lazy US summaries with batches of at most four concurrent reads. Pull to refresh, empty state, error and retry. Unsupported IAP kinds are visible but do not navigate to the pricing engine.
3. **`RegionalPricingReviewView`:** Native form for Apple US point, configured IAP base territory, Balanced preset, effective date, one Generate/Regenerate action, proposal summary, country filters (all/changes/warnings/overrides/blocked), and list navigation to detailed country pricing. The normal flow needs no per-country editing. The UI is read-only toward Apple.
4. **`RegionalPriceOverrideView`:** Current/public price, scheduled baseline, reference, suggested and selected price, tier provenance, warnings and blockers, valid Apple price-point choices, single reset and explicit country exclusion. No arbitrary numeric price input. If a refreshed override is invalid, it stays visible but blocks.
5. **`PricingSubmissionView`:** A separate exact-product/reference/date/scope/safety summary. The final **Submit Prices** action is visibly disabled and cannot send a pricing write. This is only scaffolding for Pass 4/5.

### Main-actor state and refresh rules

`RegionalPricingViewModel` is main-actor isolated with explicitly tracked idle/loading/ready/generating/reviewing phases. All network reads remain in the Pass 1/2 actor service. A request-identity token and cancellation checks prevent superseded responses from replacing newer state.

- Loading a product selects its current Apple US point **only if** its opaque point ID matches a valid US point. Unknown US prices require explicit selection.
- Generate loads the current selected product's complete reference/ladder data and invokes the deterministic Pass 2 engine. It does **not** mutate Apple.
- Choosing another US point or effective date marks the existing preview as needing regeneration. A refresh that detects different remote state marks the previous draft stale rather than replacing it. The review remains inspectable until the user explicitly regenerates.
- Valid overrides/exclusions are preserved across regeneration and local rebuild. A changed non-US base-territory override forces a new full load of dependent automatic equalizations rather than reusing stale references.
- Draft restore is always **unverified**, requires reloading Apple state, and never submits. Changing/disconnecting accounts invalidates the in-memory pricing view; drafts are account/product scoped.
- Country rows and warnings remain accessible with VoiceOver labels and Dynamic Type through native SwiftUI forms/lists. Small-iPhone/iPad layout and app themes still require device inspection.

### Review-only scenarios (prepared; not executed)

| Scenario | Expected view behavior |
| --- | --- |
| App with no lifetime/subscription products | Empty product list, no misleading price |
| Product with missing US price | Explicit select-US placeholder; Generate disabled |
| Product with 403 price read, other data available | Inline failure/unknown state, independent retry, previous proposal retained |
| Many products | Product list fetches US summaries only; country ladders lazy per chosen product |
| Generate | Async progress, complete country rows, no Apple write |
| Country row | Current/target/suggested/selected values with code and currency; warnings and future schedules distinguishable |
| Valid override/reset | Rebuild summary without new Apple write; persists draft |
| Changed reference/effective date | Needs regeneration; no silent recalculation |
| Remote snapshot changed | Previous proposal stays visible with stale-state notice; explicit re-review required |
| Restored draft/account change | No auto-submit; account scope checked |
| Blocked/country excluded | Explicit warning; excluded scope and dependent automatic effects visible |
| Submit review | Can inspect scope; final Submit disabled |
| Small widths, Dynamic Type, iPad, theme | Native list/form layout; **not visually verified** |
| Info/Xcode Cloud | Previous functionality unchanged by design; **not regression-tested** |

### Implementation limitations for next passes

- The Apple API's CSV and adjusted subscription equalization forms are still unimplemented. Affected configurations are surfaced as unsupported rather than silently approximated.
- This is a **read-only proposal UI**, not evidence that Apple price changes are safe to submit. Pass 4 must add preflight, complete schedule write contracts, frozen scope, durable operation journal, and unknown-outcome reconciliation before enabling lifetime submission. Pass 5 adds subscriber/cohort safeguards.
- Source read and manual static review only. No simulator, Xcode compiler, CI workflow, on-device screenshots, live Apple pricing verification, or automated fixture run in this session.

**Next pass when requested:** Pass 4, lifetime IAP write planning, explicit confirmation, and durable recovery **on the same PR #9**.
