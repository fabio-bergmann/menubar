#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// macOS 27's own menu bar hiding: the allowlist behind exam ("assessment")
/// mode, in the private MenuBarClientCore framework. While a restriction is
/// held, only the listed apps and system items keep their menu bar icons. It
/// lasts until invalidated or until this process exits, when macOS drops it
/// and shows everything again by itself.
///
/// Private API, so it's looked up at runtime: every class and selector is
/// checked first, and exceptions are caught rather than crashing the app.

/// YES when this macOS has the restriction (27.0 and, until Apple moves it, later).
BOOL MBRestrictionIsAvailable(void);

/// Holds a new restriction. `completion` runs once, on the main queue, within
/// 3 seconds: with the handle to keep (pass it to MBRestrictionInvalidate to
/// drop it), or an error.
void MBRestrictionActivate(NSArray<NSNumber *> *allowedSystemItems,
                           NSArray<NSString *> *allowedBundleIdentifiers,
                           void (^completion)(id _Nullable handle, NSError *_Nullable error));

/// Drops a restriction. Safe to call more than once.
void MBRestrictionInvalidate(id handle);

NS_ASSUME_NONNULL_END
