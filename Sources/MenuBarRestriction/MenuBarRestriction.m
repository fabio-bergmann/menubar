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
    @try {
        // Both take NSArray; an NSSet raises.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [(id)configurationClass alloc], initSelector, [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [(id)assertionClass new];
        if (!configuration || !assertion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, MBRestrictionError(2, @"macOS wouldn't create the restriction."));
            });
            return;
        }
        // The handler takes just an error, like the XPC call behind it.
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, activateSelector, configuration, ^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        MBRestrictionInvalidate(assertion);
                        completion(nil, error);
                    } else {
                        completion(assertion, nil);
                    }
                });
            });
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, MBRestrictionError(3, [@"macOS refused the restriction: " stringByAppendingString:reason]));
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
