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


---

## Pass 4 — Lifetime IAP submission contract, frozen preflight, journal and reconciliation

**Implementation:** Same PR #9, still targeting `develop`. Subscription writes remain disabled.

### Confirmed Apple request contract

The single supported write endpoint is `POST /v1/inAppPurchasePriceSchedules`, not one request per country. Apple defines `InAppPurchasePriceScheduleCreateRequest` with `data.type = inAppPurchasePriceSchedules`, relationships `inAppPurchase`, `baseTerritory`, `manualPrices`, and inline `inAppPurchasePrices` records linking to `inAppPurchaseV2` and `inAppPurchasePricePoint`. Price-point IDs are opaque identifiers returned by Apple; they must never be constructed from amounts.

References:
- [Create schedule request schema](https://developer.apple.com/documentation/appstoreconnectapi/inapppurchasepriceschedulecreaterequest)
- [Apple's managing-IAP-prices guide with schedule examples](https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases)
- [Price inline relationships](https://developer.apple.com/documentation/appstoreconnectapi/inapppurchasepriceinlinecreate/relationships-data.dictionary)
- [Price inline date attributes](https://developer.apple.com/documentation/appstoreconnectapi/inapppurchasepriceinlinecreate/attributes-data.dictionary)

**Synthetic redacted shape — NOT a live request:**

```json
{
  "data": {
    "type": "inAppPurchasePriceSchedules",
    "relationships": {
      "inAppPurchase": { "data": { "type": "inAppPurchases", "id": "<IAP_RESOURCE_ID>" } },
      "baseTerritory": { "data": { "type": "territories", "id": "USA" } },
      "manualPrices": { "data": [
        { "type": "inAppPurchasePrices", "id": "<PRESERVED_ROW_ID>" },
        { "type": "inAppPurchasePrices", "id": "<NEW_LOCAL_ROW_ID>" }
      ] }
    }
  },
  "included": [
    {
      "type": "inAppPurchasePrices",
      "id": "<PRESERVED_ROW_ID>",
      "attributes": { "startDate": null },
      "relationships": {
        "inAppPurchaseV2": { "data": { "type": "inAppPurchasesV2", "id": "<IAP_RESOURCE_ID>" } },
        "inAppPurchasePricePoint": { "data": { "type": "inAppPurchasePricePoints", "id": "<EXISTING_APPLE_POINT>" } }
      }
    },
    {
      "type": "inAppPurchasePrices",
      "id": "<NEW_LOCAL_ROW_ID>",
      "attributes": { "startDate": "2026-12-01" },
      "relationships": {
        "inAppPurchaseV2": { "data": { "type": "inAppPurchasesV2", "id": "<IAP_RESOURCE_ID>" } },
        "inAppPurchasePricePoint": { "data": { "type": "inAppPurchasePricePoints", "id": "<NEW_APPLE_POINT>" } }
      }
    }
  ]
}
```

Only one complete schedule payload is generated. Existing current manual entries are included as preserved records. A proposed future entry is added for changed manual/base countries; untouched automatically maintained countries remain automatic. The actual configured base territory is retained even when it is not USA. Immediate start is encoded as `null`, not an omitted attribute. Historical/multiple-window schedules and ambiguous existing dates are **blocked**, not rewritten or deleted.

### Conservative supported cases

- Verified, unmodified Apple snapshot plus a complete selected-product read, US price point, equalizations and point ladders.
- Same account, product and proposal fingerprints; selected local point IDs remain valid through fresh read-only preflight.
- No unresolved price, availability, date, future-schedule, plan or maintenance blockers.
- Existing **single unambiguous current manual price per territory** can be preserved when adding a **future-dated** change. Same-day replacement of an existing manual row is blocked pending explicit Apple schedule-replacement validation.
- **No existing future manual/automatic schedule** or complicated historical date windows. They are not discarded; the planner blocks.
- Changing an Apple base-territory price with excluded storefronts blocks because indirect effects may still reach those countries.
- Existing automatic maintenance is preserved where confirmed; automatic-to-manual transitions are shown and count as writes even if the amount is unchanged.
- No-op plans contain no POST and are displayed as such.

These are deliberate safety restrictions, not a claim that the API fundamentally cannot handle more complex schedules.

### Dispatch and recovery

- `LifetimeSchedulePlanner` is pure and produces a deterministic frozen request, preserved rows, affected/indirect/excluded storefront sets, warnings and hard blockers. The current UTC date is injected rather than read inside the planner.
- `PricingSubmissionCoordinator.shared` serializes product-level actions. Both the review sheet's preflight and the final confirmed action independently reload uncached state, reload valid Apple points, regenerate and compare the full sorted JSON body to the frozen review. No stale plan is dispatched.
- `PricingSubmissionJournal.shared` saves one device-local operation per account/product in protected Application Support, atomically, with backup exclusion. The operation is stored as `planned`, then `inFlight` **before** network dispatch, including the exact request, base territory, desired point/date/mode, preconditions, attempt count, and group ID. No API keys/JWTs are stored.
- A `201` is `accepted`, never automatically `live`. The coordinator re-reads the schedule with bounded verification attempts. It matches explicit new manual point/date rows AND dependent automatic point IDs before declaring `verifiedLive` or `verifiedScheduled` (when the start date is in the future).
- Errors with confirmed 4xx rejection become `failed`; response loss, timeout, cancellation after dispatch, or a crash leaving `inFlight` are `unknown`. A 201 that cannot yet be read becomes `pendingVerification`. No automatic POST retry occurs.
- Re-entry exposes prior result. **Reconcile with Apple** only executes GETs and updates the durable report. An unknown outcome will never be retried as a POST without a separate confirmed review; ambiguous results remain blocked from new submission.
- A crash at `planned` is provably before dispatch and permits a separately confirmed fresh request. A crash at `inFlight` remains unknown even if the send may not have occurred.
- One multi-country schedule request receives one truthful group outcome; per-territory results inherit that outcome, never fabricated partial successes.
- The existing read-only subscription UI still has no enabled Submit action.

### Fixture matrix — specified, not executed

| Situation | Expected outcome |
| --- | --- |
| No change | No payload, no remote write |
| Fresh snapshot fingerprint differs | Stale result blocks prior to write |
| Required Apple price point removed | Fresh engine fingerprint differs; regenerate |
| Non-US configured base | Preserve that base; check indirect equalizations |
| Unaffected current manual row | Include unmodified ID/point/window in schedule |
| Existing future schedule | Block pending explicit conflict resolution |
| Base changes with excluded country | Block rather than hide indirect effects |
| Confirmed 201, prices not readable yet | Accepted then pending verification; GET-only retry |
| Future-dated 201 verified | Verified scheduled, not live |
| Crash before in-flight journal | Planned record, separately confirmed new attempt allowed |
| Timeout after POST dispatch | Unknown; no automatic repeat |
| Crash during POST | Durable in-flight; GET-only re-entry reconciliation |
| HTTP 401/403/409/422/429 | Structured diagnostic, no fabricated country successes |
| Double tapping Confirm / two screens | Shared actor permits one active product submission |
| Subscription proposal | Final Submit disabled |

**Verification:** Apple public schema reviewed and source changes inspected. **No Xcode build, test suite, CI dispatch, request-fixture execution, account-authenticated Apple read or real pricing write was performed.** Integration correctness, strict Swift 6 compilation, actual API response variants, and on-device UI behavior remain **unverified**. This pass must be validated against redacted offline fixtures and compiled before any real pricing write is considered production-ready; do not use a live account for development smoke tests without separate explicit authorization.

**Next:** Pass 5, subscription price writing, preserved-subscriber policy, shared coordinator extension and final UX integration, on this same PR only upon request.


---

## Pass 5 — Standard subscription submission, subscriber consequences, per-territory recovery

**Branch / PR:** `feature/smart-regional-pricing-pass1` / #9. **Target:** `develop`. Passes 1–5 are source-implemented in this draft PR; they have **not** been compiled, fixture-tested or live-verified.

### Apple contract (read November 1, 2026)

- `POST /v1/subscriptionPrices` creates **one** new public subscription price for **one** territory per request. Relationships are `subscription` and `subscriptionPricePoint` (the opaque point ID uniquely identifies the territory).
- `attributes.startDate` can be `null` for immediate pricing, or a future ISO date. `attributes.planType` is **`UPFRONT`** for standard upfront-billed weekly/monthly/annual subscriptions. The subscription **period** is not the billing plan type. `MONTHLY` can mean monthly billing with a commitment and requires a different adjusted-point flow.
- `attributes.preserveCurrentPrice` is `true` by default when increasing the current public price, preserving that price for existing subscribers. The implementation does **not** un-preserve older cohorts.
- Apple explicitly states **decreases reach existing subscribers at renewal**, with no option to preserve a previously higher price. The UI requires explicit acknowledgment when a submitted group contains decreases. It never describes decreases as “new subscribers only.”
- Changes to existing subscribers on increases may trigger notices or consent if preservation is not used. This version does **not** support intentionally increasing existing subscribers' current price. Individual subscriber cohort outcomes cannot be proven solely by reading the subscription pricing resource.
- A future change for the same storefront and billing plan can overwrite an earlier future change. The planner **blocks** such conflicts instead of replacing them.

Source: [Apple API: Managing subscriptions](https://developer.apple.com/documentation/appstoreconnectapi/managing-auto-renewable-subscriptions), [Apple API: price changes across territories](https://developer.apple.com/documentation/appstoreconnectapi/configuring-subscription-prices-across-territories), [Apple: create attributes](https://developer.apple.com/documentation/appstoreconnectapi/subscriptionpricecreaterequest/data-data.dictionary/attributes-data.dictionary), [Apple Help: subscription price changes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/).

**Redacted fixture payload** (invented IDs and date; not a live App Store price):

```json
{
  "data": {
    "type": "subscriptionPrices",
    "attributes": {
      "startDate": "2026-12-01",
      "preserveCurrentPrice": true,
      "planType": "UPFRONT"
    },
    "relationships": {
      "subscription": {
        "data": { "type": "subscriptions", "id": "<SUBSCRIPTION_RESOURCE_ID>" }
      },
      "subscriptionPricePoint": {
        "data": { "type": "subscriptionPricePoints", "id": "<APPLE_POINT_FOR_TARGET_COUNTRY>" }
      }
    }
  }
}
```

The same request for an immediate price change uses `startDate: null`; for a decrease it uses `preserveCurrentPrice: false` and requires the decrease acknowledgment before dispatch.

### Planner and submission implementation

- `SubscriptionPricePlanner` is a **pure**, frozen planner keyed by product, territory and `UPFRONT` plan. It checks product/account/snapshot, actual plan availability, selected Apple point ownership, public (not preserved) price, current price ID/amount, existing scheduled changes, and effective date. Only true amount changes are sent; ambiguous same-amount/different-ID changes block.
- An increase sets `preserveCurrentPrice=true`. A decrease sets `false`; the UI requires acknowledgment of renewal impact. Existing preserved cohorts are read for context but are **not** used as the public baseline.
- `SubscriptionPriceCreateRequest` and `createSubscriptionPrice` are distinct from lifetime schedule payloads. The API transport does not automatically retry a POST. A valid HTTP 201 is **accepted**, not verified.
- `SubscriptionSubmissionBatch` stores the exact frozen plan and an operation record **per territory**, with planned/inFlight/accepted/verifiedLive/verifiedScheduled/pendingVerification/failed/unknown statuses, attempt count, remote ID when readable, last error and timestamp.
- The existing shared `PricingSubmissionJournal` writes the complete subscription batch atomically to a **separate protected account/product-scoped file** (backup excluded) before POST dispatch. It does not persist credentials. `PricingSubmissionCoordinator.shared` serializes product submissions across both lifetime and subscription paths.
- `submitSubscriptionConfirmed` runs fresh uncached read-only preflight, re-generates the proposal and compares the **entire encoded plan** to what the user confirmed; any mismatch blocks before writing.
- `dispatchSubscription` uses **up to three concurrent territory POSTs**, journals all three as in-flight **before** dispatch, then journals each returned result. It checks remaining territories' public baselines, existing schedules and Apple-selected price-point validity before launching each additional batch. An accepted price remains independent of any failed country—there is no invented global rollback.
- 401/403/429 stop launching new batches. 429 stores a retry deadline from numeric `Retry-After` (or a conservative 60s default). The UI displays errors and requires explicit Resume. Rejected 4xx are distinguished from ambiguous network errors.
- For each group, GET-only verification checks selected public price point, billing plan and effective date. A matching future record is **verified scheduled**, not live. The API cannot independently confirm every existing subscriber's preserved billing cohort; the report retains that uncertainty even if public price verification succeeds.
- On relaunch, opening submission review reads the account-bound journal and performs **GET-only reconciliation** of uncertain operations. In-flight/unknown statuses are never auto-retried. “Resume Remaining Countries” requires user confirmation and dispatches only *planned* or *definitively rejected/not-applied* operations after revalidating their current Apple baseline/point/availability. Accepted or verified entries are never replayed.
- Closing the sheet or moving inactive requests the shared coordinator to **pause before launching more groups**; it does not cancel a request already submitted to Apple. No background completion is promised.
- Product list surfaces an annual > 12× monthly advisory **only** for explicitly matching subscription group, group service level and currency. Unknown equivalence yields no comparison. Regional Review adds tier and unchanged filters; the pricing product list no longer displays developer-preview copy.

### Supported and blocked matrix

| Configuration | Status |
| --- | --- |
| Standard upfront weekly, monthly or annual subscription, sole `UPFRONT` plan | Supported by the source-level submission implementation |
| Valid Apple local price point, fresh public price and availability, no upcoming conflicts | Planned for one territory POST |
| Existing subscribers during price increases | Preserve current public price by default; older preserved cohorts not changed |
| Existing subscribers during price decreases | Acknowledgment required; all existing subscriptions can renew at lower price |
| Subscription with existing future price change in same territory/plan | **Blocked**, never overwrite silently |
| `MONTHLY` commitment billing plan, mixed `UPFRONT`/`MONTHLY`, or adjusted equalization/CSV-only case | **Blocked** until separate plan-aware support |
| Unknown country, missing point, missing currency, 403/404 data gaps | Visible warning/blocker; never invent or submit point |
| Accepted POST with delayed Apple price read | Pending verification; no repeat POST |
| Timeout or crash after dispatch | Unknown; GET-only reconciliation before any subsequent confirmed action |
| Partial successful batch | Per-territory report; accepted/verified entries excluded from retries |
| Permission denied | Actionable Apple error; read-only browsing and saved proposal remain available |
| All no-op prices | No POST |
| Lifetime product | Existing Pass 4 single-schedule path unchanged |

### Offline/manual release checklist — NOT executed

1. **Compile first:** strict Swift 6 iOS target and checked-in Xcode project plus XcodeGen-generated file membership. No current build result exists.
2. Inspect native Pricing → product → Generate → Review → Country → final confirmation on actual iPhone (Dynamic Type, VoiceOver, iPad if supported); verify subscription/lifetime separation and existing app-detail modes.
3. With an injected URLSession and **redacted fixtures**, verify Apple request JSON (UPFRONT, date null/date string, preserve true/false), journal recovery, 201 vs delayed GET, 401/403/409/422/429, rate limit deadline, partial success/failure, crash/timeout unknown, and maximal in-flight count ≤3.
4. Verify plan-availability and `planType` decoding from real **read-only**, separately authorized Apple API access before enabling commercial use. Confirm all Apple price points/currencies and mapping coverage against current territories.
5. Test both existing and new pricing schedules: future conflicts, preserved subscribers, increases/decreases, and no-op. Confirm absence of POST on all preview/generation/reconciliation paths.
6. Verify cancellation, app suspension, disconnection, relaunch and explicit Resume on a fixture session. Ensure old accounts' journals do not resume after credential rotation.
7. Review with the account holder before any live price mutation. **No live price-changing test was authorized or performed.**

**Release assessment:** Passes 1–5 are implemented as source changes, but **not production-validated**. There is no successful build/test/fixture run or verified Apple production response for this PR. Treat all write functionality as unsafe for real money-changing use until authorized validation is completed and code-review findings resolved.
