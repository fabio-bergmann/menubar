#import "MenuBarRestriction.h"
#import <dlfcn.h>
#import <objc/message.h>

#if !__has_feature(objc_arc)
#error "MenuBarRestriction is written for ARC"
#endif

static NSString *const MBRestrictionErrorDomain = @"dev.fabio.menubar.restriction";

static Class configurationClass;
static Class assertionClass;
static SEL initSelector;
static SEL activateSelector;
static SEL invalidateSelector;

static void MBRestrictionLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW)) {
            return;
        }
        initSelector = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        activateSelector = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        invalidateSelector = NSSelectorFromString(@"invalidate");
        Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
        if ([configuration instancesRespondToSelector:initSelector] &&
            [assertion instancesRespondToSelector:activateSelector] &&
            [assertion instancesRespondToSelector:invalidateSelector]) {
            configurationClass = configuration;
            assertionClass = assertion;
        }
    });
}

static NSError *MBRestrictionError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:MBRestrictionErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL MBRestrictionIsAvailable(void) {
    MBRestrictionLoad();
    return configurationClass != nil && assertionClass != nil;
}

void MBRestrictionActivate(NSArray<NSNumber *> *allowedSystemItems,
                           NSArray<NSString *> *allowedBundleIdentifiers,
                           void (^completion)(id _Nullable handle, NSError *_Nullable error)) {
    if (!MBRestrictionIsAvailable()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, MBRestrictionError(1, @"This macOS doesn't have the menu bar restriction."));
        });
        return;
    }
    // MenuBarAgent answers on a queue of its own, and nothing promises it
    // answers once, or at all. `finish` only ever runs on the main queue, so
    // its flags need no lock: the first answer wins, the timeout included.
    __block id assertion = nil;
    __block BOOL answered = NO;
    __block BOOL timedOut = NO;
    // The reply block below keeps `finish` and so `assertion` alive, and the
    // assertion keeps the reply block: a cycle that holds the assertion, and
    // its connection to MenuBarAgent, until the app quits. Clearing the
    // variable once it's settled breaks it; the caller's handle is the only
    // reference left, and dropping that closes the connection.
    void (^finish)(NSError *) = ^(NSError *error) {
        if (answered) {
            // A yes that arrives after the timeout gave up on it: drop it, or
            // it would stay held with nothing keeping track of it.
            if (timedOut && !error && assertion) MBRestrictionInvalidate(assertion);
            if (timedOut) assertion = nil;
            return;
        }
        answered = YES;
        if (error) {
            if (assertion) MBRestrictionInvalidate(assertion);
            completion(nil, error);
        } else {
            completion(assertion, nil);
        }
        // After a timeout the assertion is kept for a late answer, above.
        if (!timedOut) assertion = nil;
    };
    @try {
        // init consumes the object alloc returned and hands back a retained
        // one, or nil; ARC has to be told, or a nil would free it twice.
        typedef id __attribute__((ns_returns_retained)) (*InitFunction)(
            id __attribute__((ns_consumed)), SEL, NSArray *, NSArray *);
        // Both take NSArray; an NSSet raises.
        id configuration = ((InitFunction)objc_msgSend)(
            [(id)configurationClass alloc], initSelector, [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        assertion = [(id)assertionClass new];
        if (!configuration || !assertion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                finish(MBRestrictionError(2, @"macOS wouldn't create the restriction."));
            });
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (answered) return;
            timedOut = YES;
            finish(MBRestrictionError(4, @"macOS didn't answer within 3 seconds."));
        });
        // The handler takes just an error, like the XPC call behind it.
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, activateSelector, configuration, ^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{ finish(error); });
            });
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name;
        dispatch_async(dispatch_get_main_queue(), ^{
            finish(MBRestrictionError(3, [@"macOS refused the restriction: " stringByAppendingString:reason]));
        });
    }
}

void MBRestrictionInvalidate(id handle) {
    if (!invalidateSelector || ![handle respondsToSelector:invalidateSelector]) return;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(handle, invalidateSelector);
    } @catch (NSException *exception) {
        NSLog(@"MenuBarRestriction: invalidate raised %@", exception);
    }
}
