![TikTok Annoyance](assets/banner.png)

# TikTok Annoyance

Rootless Theos/Logos tweak for Dopamine + ElleKit, targeting **TikTok 47.1.0 (471044)**, bundle `com.zhiliaoapp.musically`. Builds arm64 for the App Store process; minimum iOS 15.0. Other TikTok versions leave hooks disabled.

Removes Shop entries from top-tab configuration/results. Filters the runtime-confirmed `AWEHotListDataController` (type 0) refresh, load-more, response lists and conversion inputs before insertion, with additional protection for feed data operator inserts. The original source setter is untouched, keeping native queue construction and item-to-index map updates together. Removes posts marked as ads/soft ads, live previews, product attachments, branded content or promoted ads. Ordinary videos from creators who happen to be live remain. Music/effect anchors are preserved unless commerce metadata identifies them as product links.

Private selectors and signatures were extracted from the supplied decrypted 47.1.0 IPA. Numeric For You gating is based on the app's `TTKFeedDataOperator.p_isFYPType` implementation, which compares its type to zero. Runtime checks gate the hook groups. No broad UIKit hooks, network interception, captions or account IDs are used. Settings are saved in TikTok’s own NSUserDefaults with a TikTokAnnoyance prefix. Filtering preserves post order, server pagination and the existing load-more mechanism.

## Build

Run `./tools/build.sh`. The wrapper copies the build inputs into a temporary directory because Theos does not support project paths containing spaces. Uses the existing `/Users/evan/theos`, iOS 16.5 SDK and installed Xcode; set `THEOS` to override the toolchain path.

Run `python3 tools/test_filters.py` for host-side filtering tests using the actual helper implementation and fixture model objects. Metadata evidence is in `inspection/`; `tools/inspect_objc.py` reads arm64 Objective-C metadata without executing the binary.

## Device test

Install `packages/local.evans.tiktokblocker_0.2.2_iphoneos-arm64.deb` with Sileo or `sudo dpkg -i <package-path>`. Close and reopen TikTok; a respring is unnecessary. Ensure Choicy permits this tweak in TikTok.

Verify Shop is absent; scroll and pull to refresh through multiple For You batches; check that ordinary posts remain while shopping cart posts, ads, sponsored/promotional labels and live previews are absent. Check Following and profile feeds still work. Repeat after relaunch. An entirely blocked server batch remains empty; there is no automatic retry loop.

Runtime messages use `[TikTokBlocker]` and report enabled hook groups, batch counts and tab removals without post IDs. A bounded (128 KiB) log is also kept in TikTok’s `Library/Caches/TikTokBlocker.log`. A build or fixture-test pass does not establish device behavior.

Disable this package for TikTok in Choicy, or uninstall with `sudo dpkg -r local.evans.tiktokblocker`, then close and reopen TikTok. No other tweaks need disabling.

## Limits

Product URL markers and nonzero branded-content metadata are classifiers that need live validation against this build's server payloads. Content without Shop/commercial markers cannot be reliably recognized. Future server-configured commerce attachments or additional queue replacement paths may require further hooks. Version/signature gating prevents silently applying these hooks to a different app build.

## Validation recorded

- Host: arm64 compilation, link, signing and rootless Debian packaging passed; filtering fixture tests passed.
- Package inspected: only the tweak dylib and app-specific filter under `/var/jb/Library/MobileSubstrate/DynamicLibraries`; dependencies `firmware (>= 15.0), ellekit`.
- Device: installed on the authorized iPhone 14 Pro Max running iOS 16.2, Dopamine/ElleKit 1.2, TikTok 47.1.0. TikTok restarted successfully. App-local log confirms `queue=1 tabs=1` and `removed Shop tab` twice.
- Pending: visual Shop confirmation and live For You refresh/load-more filtering, including all requested content categories. Hook activation alone does not establish queue behavior.

### 0.1.2 correction

The original 0.1.0 loaded but did not receive any feed batches on this phone. Temporary 0.1.1 diagnostics established that the active For You source is `AWEHotListDataController`, type 0, rather than `AWESmartFeedDataController`. The 0.1.2 hooks target that class's own implementations; diagnostics were removed. Device log confirms the new hooks activated, preserved ordinary six-post batches, and removed a seven-post batch classified as ads. LIVE and Shop attachment behavior still requires user confirmation. Category counts are recorded in the bounded app-local log.

### 0.1.3 queue-gap correction

Filtering now happens before `handleResponseModel:pullSuccess:` / `handleResponseModel:pullType:pullSuccess:` and before conversion, rather than shortening a converted result or substituting a shorter array in `setDataSource:`. This addresses a possible mismatch between the list used for playback/index bookkeeping and the final backing queue. Auxiliary `liveList` previews are cleared before response processing. Explicit `status.deleted` / `status.isProhibited` entries are removed; an unset `isCanPlay` flag alone is not treated as unavailable.

Regression tests verify that response filtering precedes native queue/index construction, the resulting indexes are contiguous, deleted entries are removed, repeat calls are idempotent, and cursor/hasMore pagination fields remain intact. Device scrolling must confirm whether the reported unavailable-video skip is resolved.

### 0.2.0 in-app settings

Profile → top-right menu → **TikTok Annoyance**, directly after **Settings and privacy**, with a separator above the added row. The existing menu entries and native cell/index data remain intact. The row follows menu scrolling, sizing and the Settings row’s text style, and opens a native switch list with Done.

Independent, persistent switches: Hide Shop tab, Shop attachment posts, Ads, Sponsored posts, LIVE streams, Promotional content, Unavailable videos. Defaults are enabled to preserve previous behavior. Refresh For You after changing filters; reopen TikTok to rebuild Shop tabs. A post matching another enabled category remains hidden. Sponsored detection uses the soft-ad marker or an explicit Sponsored ad label; other ad markers use Ads. Branded-content markers use Promotional content.

The host tests cover every switch’s disabled state, independence from Shop-tab visibility, all-off behavior, and preservation of the auxiliary live list when LIVE filtering is disabled. Build, packaging and phone installation passed. Visual menu placement and persisted switch operation still require device confirmation.

### 0.2.1 glyph and Shop attachment coverage

The menu entry uses the native SF Symbols `slider.horizontal.3` glyph, aligned with the Settings row and sharing its tap target. User confirmed the 0.2.0 entry’s placement and that it opens the switches.

Shop detection additionally uses verified `+hasProductAnchorWithAwemeModel:` on `TTKECSearchVideoProductAnchorView`, structured product/commodity identifiers in attachment extras, and type 35 (selected by TikTok’s `+generateShopAnchorModelWithAwemeModel:` implementation). It never filters by product name or caption. Tests cover JSON-only product attachments, native-predicate attachments, Shop-store anchors, ordinary effect extras and switch-off behavior. The reported shirt-video example has not been directly captured or verified removed on device.

### 0.2.2 public release

New package icon and matching Sileo depiction. Filtering behavior matches 0.2.1.

Add [sonicedc’s repository](https://sonicedc.github.io) in Sileo, then install TikTok Annoyance. [Latest release](https://github.com/Sonicedc/TikTok-Annoyance/releases/latest).
