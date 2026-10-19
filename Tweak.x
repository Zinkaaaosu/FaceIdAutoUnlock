// FaceAutoUnlock v5 — срабатывает ОДИН раз на каждую разблокировку Face ID.
// Триггер — момент перехода keybag из "заблокирован" в 0 (разблокирован).
// Пока keybag остаётся 0, повторных срабатываний нет (шторка уведомлений больше не закрывается).
// Лог: /var/mobile/fau.log

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
- (void)unlockUIFromSource:(int)source withOptions:(id)options;
- (void)lockScreenViewControllerRequestsUnlock;
@end

typedef int (*MKBGetDeviceLockState_t)(CFDictionaryRef);

static MKBGetDeviceLockState_t gMKB = NULL;
static dispatch_source_t gTimer = nil;
static BOOL gBusy = NO;
static BOOL gPending = NO;
static int gPrevKB = -99;
static CFAbsoluteTime gEdgeTime = 0;

static void FAU_Write(NSString *line) {
    FILE *f = fopen("/var/mobile/fau.log", "a");
    if (f) {
        fprintf(f, "%.3f %s\n", CFAbsoluteTimeGetCurrent(), [line UTF8String]);
        fclose(f);
    }
}

// Шаги 0-3: основной способ (B), шаг 4: запасной (A)
static void FAU_Step(SBLockScreenManager *mgr, int step) {
    @try {
        if (![mgr isUILocked]) {
            if (step > 0) FAU_Write([NSString stringWithFormat:@"unlocked after step %d", step - 1]);
            gBusy = NO;
            return;
        }
        if (step >= 5) {
            FAU_Write(@"gave up");
            gBusy = NO;
            return;
        }

        if (step < 4 && [mgr respondsToSelector:@selector(lockScreenViewControllerRequestsUnlock)]) {
            [mgr lockScreenViewControllerRequestsUnlock];
        } else {
            [mgr unlockUIFromSource:12 withOptions:nil];
        }
    } @catch (__unused NSException *e) {
        FAU_Write(@"exception in unlock");
        gBusy = NO;
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        FAU_Step(mgr, step + 1);
    });
}

static void FAU_Tick(void) {
    int kb = gMKB ? gMKB(NULL) : -1;

    if (kb != 0) {            // телефон заблокирован — сбрасываем и ждём следующего Face ID
        gPending = NO;
        gPrevKB = kb;
        return;
    }

    if (gPrevKB != 0) {       // переход в "разблокирован" — это и есть момент Face ID
        gPending = YES;
        gEdgeTime = CFAbsoluteTimeGetCurrent();
        FAU_Write(@"edge: keybag -> 0");
    }
    gPrevKB = kb;

    if (!gPending || gBusy) return;

    // Окно действия — 2 секунды после Face ID, дальше не вмешиваемся
    if (CFAbsoluteTimeGetCurrent() - gEdgeTime > 2.0) {
        gPending = NO;
        return;
    }

    Class cls = objc_getClass("SBLockScreenManager");
    if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return;

    SBLockScreenManager *mgr = [cls sharedInstance];
    if (!mgr) return;
    if (![mgr respondsToSelector:@selector(isUILocked)]) return;
    if (![mgr respondsToSelector:@selector(unlockUIFromSource:withOptions:)]) return;
    if (![mgr isUILocked]) return;   // UI ещё не на экране блокировки — ждём в пределах окна

    gPending = NO;   // один раз
    gBusy = YES;
    FAU_Step(mgr, 0);
}

static void FAU_Start(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY);
    if (h) gMKB = (MKBGetDeviceLockState_t)dlsym(h, "MKBGetDeviceLockState");
    FAU_Write(gMKB ? @"MKBGetDeviceLockState found" : @"MKBGetDeviceLockState NOT found");
    if (!gMKB) return;

    gTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                              (uint64_t)(0.05 * NSEC_PER_SEC),
                              (uint64_t)(0.01 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gTimer, ^{ FAU_Tick(); });
    dispatch_resume(gTimer);
}

%ctor {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:@"com.apple.springboard"]) return;
        FAU_Write(@"LOADED");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ FAU_Start(); });
    }
}
