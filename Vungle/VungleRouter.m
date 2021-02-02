//
//  VungleRouter.m
//  MoPubSDK
//
//  Copyright (c) 2015 MoPub. All rights reserved.
//

#import <VungleSDK/VungleSDKHeaderBidding.h>
#if __has_include("MoPub.h")
    #import "MPLogging.h"
    #import "MPRewardedVideo.h"
    #import "MPRewardedVideoError.h"
    #import "MoPub.h"
#endif
#import "VungleAdapterConfiguration.h"
#import "VungleInstanceMediationSettings.h"
#import "VungleRouter.h"

NSString *const kVungleAppIdKey = @"appId";
NSString *const kVunglePlacementIdKey = @"pid";
NSString *const kVungleUserId = @"userId";
NSString *const kVungleOrdinal = @"ordinal";
NSString *const kVungleStartMuted = @"muted";
NSString *const kVungleSupportedOrientations = @"orientations";
NSString *const kVungleAdEventId = @"event_id";

NSString *const kVungleSDKCollectDevice = @"collectDevice";
NSString *const kVungleSDKMinSpaceForInit = @"vungleMinimumFileSystemSizeForInit";
NSString *const kVungleSDKMinSpaceForAdRequest = @"vungleMinimumFileSystemSizeForAdRequest";
NSString *const kVungleSDKMinSpaceForAssetLoad = @"vungleMinimumFileSystemSizeForAssetDownload";

const CGSize kVNGMRECSize = {.width = 300.0f, .height = 250.0f};
const CGSize kVNGBannerSize = {.width = 320.0f, .height = 50.0f};
const CGSize kVNGShortBannerSize = {.width = 300.0f, .height = 50.0f};
const CGSize kVNGLeaderboardBannerSize = {.width = 728.0f, .height = 90.0f};

typedef NS_ENUM(NSUInteger, SDKInitializeState) {
    SDKInitializeStateNotInitialized,
    SDKInitializeStateInitializing,
    SDKInitializeStateInitialized
};

@interface VungleRouter ()

@property (nonatomic, copy) NSString *vungleAppID;
@property (nonatomic) BOOL isAdPlaying;
@property (nonatomic) SDKInitializeState sdkInitializeState;

@property (nonatomic) NSMutableDictionary *waitingListDict;
@property (nonatomic) NSMutableDictionary *hbWaitingListDict;
@property (nonatomic) NSMapTable<NSString *, id<VungleRouterDelegate>> *delegatesDict;
@property (nonatomic) NSMapTable<NSString *, id<VungleRouterDelegate>> *hbDelegatesDict;
@property (nonatomic) NSMapTable<NSString *, id<VungleRouterDelegate>> *bannerDelegates;
@property (nonatomic) NSMapTable<NSString *, id<VungleRouterDelegate>> *hbBannerDelegates;

@end

@implementation VungleRouter

- (instancetype)init
{
    if (self = [super init]) {
        self.sdkInitializeState = SDKInitializeStateNotInitialized;
        self.delegatesDict = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                                                   valueOptions:NSPointerFunctionsWeakMemory];
        self.waitingListDict = [NSMutableDictionary dictionary];
        self.bannerDelegates = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                                                     valueOptions:NSPointerFunctionsWeakMemory];
        self.hbWaitingListDict = [NSMutableDictionary dictionary];
        self.hbDelegatesDict = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                                                     valueOptions:NSPointerFunctionsWeakMemory];
        self.hbBannerDelegates = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                                                       valueOptions:NSPointerFunctionsWeakMemory];
        self.isAdPlaying = NO;
    }
    return self;
}

+ (VungleRouter *)sharedRouter
{
    static VungleRouter * sharedRouter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedRouter = [[VungleRouter alloc] init];
    });
    return sharedRouter;
}

- (void)collectConsentStatusFromMoPub
{
    // Collect and pass the user's consent from MoPub onto the Vungle SDK
    if ([[MoPub sharedInstance] isGDPRApplicable] == MPBoolYes) {
        if ([[MoPub sharedInstance] allowLegitimateInterest] == YES) {
            if ([[MoPub sharedInstance] currentConsentStatus] == MPConsentStatusDenied
                || [[MoPub sharedInstance] currentConsentStatus] == MPConsentStatusDoNotTrack
                || [[MoPub sharedInstance] currentConsentStatus] == MPConsentStatusPotentialWhitelist) {
                [[VungleSDK sharedSDK] updateConsentStatus:(VungleConsentDenied) consentMessageVersion:@""];
            } else {
                [[VungleSDK sharedSDK] updateConsentStatus:(VungleConsentAccepted) consentMessageVersion:@""];
            }
        } else {
            BOOL canCollectPersonalInfo = [[MoPub sharedInstance] canCollectPersonalInfo];
            [[VungleSDK sharedSDK] updateConsentStatus:(canCollectPersonalInfo) ? VungleConsentAccepted : VungleConsentDenied consentMessageVersion:@""];
        }
    }
}

- (void)initializeSdkWithInfo:(NSDictionary *)info
{
    NSString *appId = [info objectForKey:kVungleAppIdKey];

    if (!self.vungleAppID) {
        self.vungleAppID = appId;
    }
    static dispatch_once_t vungleInitToken;
    dispatch_once(&vungleInitToken, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
        [[VungleSDK sharedSDK] performSelector:@selector(setPluginName:version:) withObject:@"mopub" withObject:[[[VungleAdapterConfiguration alloc] init] adapterVersion]];
#pragma clang diagnostic pop
       
        // Get delegate instance and set init options
        NSString *placementID = [info objectForKey:kVunglePlacementIdKey];
        id<VungleRouterDelegate> delegateInstance = [self.waitingListDict objectForKey:placementID];
        NSMutableDictionary *initOptions = [NSMutableDictionary dictionary];
        
        if (placementID.length && delegateInstance) {
            [initOptions setObject:placementID forKey:VungleSDKInitOptionKeyPriorityPlacementID];

            NSInteger priorityPlacementAdSize = 1;
            if ([delegateInstance respondsToSelector:@selector(getBannerSize)]) {
                CGSize size = [delegateInstance getBannerSize];
                priorityPlacementAdSize = [self getVungleBannerAdSizeType:size];
                [initOptions setObject:[NSNumber numberWithInteger:priorityPlacementAdSize] forKey:VungleSDKInitOptionKeyPriorityPlacementAdSize];
            }
        }
              
        self.sdkInitializeState = SDKInitializeStateInitializing;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError * error = nil;
            // Disable refresh functionality for all banners
            [[VungleSDK sharedSDK] disableBannerRefresh];
            BOOL started = [[VungleSDK sharedSDK] startWithAppId:appId options:initOptions error:&error];
            if (!started && error.code == VungleSDKErrorSDKAlreadyInitializing) {
                MPLogInfo(@"Vungle:SDK already has been initialized.");
                self.sdkInitializeState = SDKInitializeStateInitialized;
                [self clearWaitingList];
            }
            [[VungleSDK sharedSDK] setDelegate:self];
            [[VungleSDK sharedSDK] setNativeAdsDelegate:self];
            [[VungleSDK sharedSDK] setSdkHBDelegate:self];
        });
    });
}

- (void)setShouldCollectDeviceId:(BOOL)shouldCollectDeviceId
{
    // This should ONLY be set if the SDK has not been initialized
    if (self.sdkInitializeState == SDKInitializeStateNotInitialized) {
        [VungleSDK setPublishIDFV:shouldCollectDeviceId];
    }
}

- (void)setSDKOptions:(NSDictionary *)sdkOptions
{
    // right now, this is just for the checks used to verify amount of
    // storage available before attempting specific operations
    if (sdkOptions[kVungleSDKMinSpaceForInit]) {
        NSNumber *minSizeForInit = sdkOptions[kVungleSDKMinSpaceForInit];
        if ([minSizeForInit isEqual:@(0)] && [[NSUserDefaults standardUserDefaults] valueForKey:kVungleSDKMinSpaceForInit]) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVungleSDKMinSpaceForInit];
        } else if (minSizeForInit.integerValue > 0) {
            [[NSUserDefaults standardUserDefaults] setInteger:minSizeForInit.intValue forKey:kVungleSDKMinSpaceForInit];
        }
    }
    
    if (sdkOptions[kVungleSDKMinSpaceForAdRequest]) {
        NSNumber *tempAdRequest = sdkOptions[kVungleSDKMinSpaceForAdRequest];
        
        if ([tempAdRequest isEqual:@(0)] && [[NSUserDefaults standardUserDefaults] valueForKey:kVungleSDKMinSpaceForAdRequest]) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVungleSDKMinSpaceForAdRequest];
        } else if (tempAdRequest.integerValue > 0) {
            [[NSUserDefaults standardUserDefaults] setInteger:tempAdRequest.intValue forKey:kVungleSDKMinSpaceForAdRequest];
        }
    }
    
    if (sdkOptions[kVungleSDKMinSpaceForAssetLoad]) {
        NSNumber *tempAssetLoad = sdkOptions[kVungleSDKMinSpaceForAssetLoad];
        
        if ([tempAssetLoad isEqual:@(0)] && [[NSUserDefaults standardUserDefaults] valueForKey:kVungleSDKMinSpaceForAssetLoad]) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVungleSDKMinSpaceForAssetLoad];
        } else if (tempAssetLoad.integerValue > 0) {
            [[NSUserDefaults standardUserDefaults] setInteger:tempAssetLoad.intValue forKey:kVungleSDKMinSpaceForAssetLoad];
        }
    }
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)requestInterstitialAdWithCustomEventInfo:(NSDictionary *)info
                                        delegate:(id<VungleRouterDelegate>)delegate
{
    [self collectConsentStatusFromMoPub];
    
    if ([self validateInfoData:info]) {
        if (self.sdkInitializeState == SDKInitializeStateNotInitialized) {
            [self addToWaitingListWithDelegate:delegate];
            [self initializeSdkWithInfo:info];
        }
        else if (self.sdkInitializeState == SDKInitializeStateInitializing) {
            [self addToWaitingListWithDelegate:delegate];
        }
        else if (self.sdkInitializeState == SDKInitializeStateInitialized) {
            [self requestAdWithCustomEventInfo:info delegate:delegate];
        }
    } else {
        [delegate vungleAdDidFailToLoad:nil];
    }
}

- (void)requestRewardedVideoAdWithCustomEventInfo:(NSDictionary *)info
                                         delegate:(id<VungleRouterDelegate>)delegate
{
    [self collectConsentStatusFromMoPub];
    
    if ([self validateInfoData:info]) {
        if (self.sdkInitializeState == SDKInitializeStateNotInitialized) {
            [self addToWaitingListWithDelegate:delegate];
            [self initializeSdkWithInfo:info];
        }
        else if (self.sdkInitializeState == SDKInitializeStateInitializing) {
            [self addToWaitingListWithDelegate:delegate];
        }
        else if (self.sdkInitializeState == SDKInitializeStateInitialized) {
            [self requestAdWithCustomEventInfo:info delegate:delegate];
        }
    } else {
        NSError *error = [NSError errorWithDomain:MoPubRewardedVideoAdsSDKDomain code:MPRewardedVideoAdErrorUnknown userInfo:nil];
        [delegate vungleAdDidFailToLoad:error];
    }
}

- (void)requestBannerAdWithCustomEventInfo:(NSDictionary *)info
                                      size:(CGSize)size
                                  delegate:(id<VungleRouterDelegate>)delegate
{
    [self collectConsentStatusFromMoPub];
    
    if ([self validateInfoData:info] && (CGSizeEqualToSize(size, kVNGMRECSize) ||
                                         CGSizeEqualToSize(size, kVNGBannerSize) ||
                                         CGSizeEqualToSize(size, kVNGLeaderboardBannerSize) ||
                                         CGSizeEqualToSize(size, kVNGShortBannerSize))) {
        if (self.sdkInitializeState == SDKInitializeStateNotInitialized) {
            [self addToWaitingListWithDelegate:delegate];
            [self initializeSdkWithInfo:info];
        } else if (self.sdkInitializeState == SDKInitializeStateInitializing) {
            [self addToWaitingListWithDelegate:delegate];
        } else if (self.sdkInitializeState == SDKInitializeStateInitialized) {
            [self requestBannerAdWithDelegate:delegate];
        }
    } else {
        MPLogError(@"Vungle: A banner ad type was requested with the size which Vungle SDK doesn't support.");
        [delegate vungleAdDidFailToLoad:nil];
    }
}

- (void)requestAdWithCustomEventInfo:(NSDictionary *)info
                            delegate:(id<VungleRouterDelegate>)delegate
{
    NSString *placementId = [delegate getPlacementID];
    NSString *eventId = [delegate getEventId];
    if (eventId.length > 0) {
        if (![self.hbDelegatesDict objectForKey:eventId]) {
            [self.hbDelegatesDict setObject:delegate forKey:eventId];
        }
    } else {
        if (![self.delegatesDict objectForKey:placementId]) {
            [self.delegatesDict setObject:delegate forKey:placementId];
        }
    }
    
    if ([self isAdAvailableForDelegate:delegate]) {
        [delegate vungleAdDidLoad];
        return;
    }

    NSError *error = nil;
    if ([[VungleSDK sharedSDK] loadPlacementWithID:placementId adMarkup:[delegate getAdMarkup] error:&error]) {
        MPLogInfo(@"Vungle: Start to load an ad for Placement ID :%@", placementId);
    } else {
        if (error) {
            MPLogError(@"Vungle: Unable to load an ad for Placement ID :%@, Error %@", placementId, error);
        }
        [delegate vungleAdDidFailToLoad:error];
    }
}

- (void)requestBannerAdWithDelegate:(id<VungleRouterDelegate>)delegate
{
    @synchronized (self) {
        NSString *placementID = [delegate getPlacementID];
        NSString *eventId = [delegate getEventId];
        CGSize size = [delegate getBannerSize];
        if (eventId.length > 0) {
            if (![self.hbBannerDelegates objectForKey:eventId]) {
                [self.hbBannerDelegates setObject:delegate forKey:eventId];
            }
        } else {
            if (![self.bannerDelegates objectForKey:placementID]) {
                [self.bannerDelegates setObject:delegate forKey:placementID];
            }
        }
        
        if ([self isBannerAdAvailableForDelegate:delegate]) {
            MPLogInfo(@"Vungle: Banner ad already cached for Placement ID :%@", placementID);
            delegate.bannerState = BannerRouterDelegateStateCached;
            [delegate vungleAdDidLoad];
        } else {
            delegate.bannerState = BannerRouterDelegateStateRequesting;
            
            NSError *error = nil;
            if (CGSizeEqualToSize(size, kVNGMRECSize)) {
                if ([[VungleSDK sharedSDK] loadPlacementWithID:placementID adMarkup:[delegate getAdMarkup] error:&error]) {
                    MPLogInfo(@"Vungle: Start to load an ad for Placement ID :%@", placementID);
                } else {
                    [self requestBannerAdFailedWithError:error
                                             placementID:placementID
                                                delegate:delegate];
                }
            } else {
                if ([[VungleSDK sharedSDK] loadPlacementWithID:placementID adMarkup:[delegate getAdMarkup] withSize:[self getVungleBannerAdSizeType:size] error:&error]) {
                    MPLogInfo(@"Vungle: Start to load an ad for Placement ID :%@", placementID);
                } else {
                    [self requestBannerAdFailedWithError:error
                                             placementID:placementID
                                                delegate:delegate];
                }
            }
        }
    }
}

- (BOOL)isAdAvailableForDelegate:(id<VungleRouterDelegate>)delegate
{
    return [[VungleSDK sharedSDK] isAdCachedForPlacementID:[delegate getPlacementID] adMarkup:[delegate getAdMarkup]];
}

- (BOOL)isBannerAdAvailableForDelegate:(id<VungleRouterDelegate>)delegate
{
    CGSize size = [delegate getBannerSize];
    NSString *placementId = [delegate getPlacementID];
    NSString *adMarkup = [delegate getAdMarkup];
    if (CGSizeEqualToSize(size, kVNGMRECSize)) {
        return [[VungleSDK sharedSDK] isAdCachedForPlacementID:placementId adMarkup:adMarkup];
    }

    return [[VungleSDK sharedSDK] isAdCachedForPlacementID:placementId adMarkup:adMarkup
                                                  withSize:[self getVungleBannerAdSizeType:size]];
}

- (NSString *)currentSuperToken {
    return [[VungleSDK sharedSDK] currentSuperToken];
}

- (void)presentInterstitialAdFromViewController:(UIViewController *)viewController
                                        options:(NSDictionary *)options
                                       delegate:(id<VungleRouterDelegate>)delegate
{
    NSString *placementId = [delegate getPlacementID];
    if (!self.isAdPlaying && [self isAdAvailableForDelegate:delegate]) {
        self.isAdPlaying = YES;
        NSError *error = nil;
        BOOL success = [[VungleSDK sharedSDK] playAd:viewController options:options placementID:placementId adMarkup:[delegate getAdMarkup] error:&error];
        if (!success) {
            [delegate vungleAdDidFailToPlay:error ?: [NSError errorWithCode:MOPUBErrorVideoPlayerFailedToPlay localizedDescription:@"Failed to play Vungle Interstitial Ad."]];
            self.isAdPlaying = NO;
        }
    } else {
        [delegate vungleAdDidFailToPlay:nil];
    }
}

- (void)presentRewardedVideoAdFromViewController:(UIViewController *)viewController
                                      customerId:(NSString *)customerId
                                        settings:(VungleInstanceMediationSettings *)settings
                                        delegate:(id<VungleRouterDelegate>)delegate
{
    NSString *placementId = [delegate getPlacementID];
    if (!self.isAdPlaying && [self isAdAvailableForDelegate:delegate]) {
        self.isAdPlaying = YES;
        NSMutableDictionary *options = [NSMutableDictionary dictionary];
        if (customerId.length > 0) {
            options[VunglePlayAdOptionKeyUser] = customerId;
        } else if (settings && settings.userIdentifier.length > 0) {
            options[VunglePlayAdOptionKeyUser] = settings.userIdentifier;
        }
        if (settings.ordinal > 0) {
            options[VunglePlayAdOptionKeyOrdinal] = @(settings.ordinal);
        }
        if (settings.startMuted) {
            options[VunglePlayAdOptionKeyStartMuted] = @(settings.startMuted);
        }
        
        int appOrientation = [settings.orientations intValue];
        if (appOrientation == 0 && [VungleAdapterConfiguration orientations] != nil) {
            appOrientation = [[VungleAdapterConfiguration orientations] intValue];
        }
        
        NSNumber *orientations = @(UIInterfaceOrientationMaskAll);
        if (appOrientation == 1) {
            orientations = @(UIInterfaceOrientationMaskLandscape);
        } else if (appOrientation == 2) {
            orientations = @(UIInterfaceOrientationMaskPortrait);
        }
        
        options[VunglePlayAdOptionKeyOrientations] = orientations;
        
        NSError *error = nil;
        BOOL success = [[VungleSDK sharedSDK] playAd:viewController options:options placementID:placementId adMarkup:[delegate getAdMarkup] error:&error];
        
        if (!success) {
            [delegate vungleAdDidFailToPlay:error ?: [NSError errorWithCode:MOPUBErrorVideoPlayerFailedToPlay localizedDescription:@"Failed to play Vungle Rewarded Video Ad."]];
            self.isAdPlaying = NO;
        }
    } else {
        NSError *error = [NSError errorWithDomain:MoPubRewardedVideoAdsSDKDomain code:MPRewardedVideoAdErrorNoAdsAvailable userInfo:nil];
        [delegate vungleAdDidFailToPlay:error];
    }
}

- (UIView *)renderBannerAdInView:(UIView *)bannerView
                        delegate:(id<VungleRouterDelegate>)delegate
                         options:(NSDictionary *)options
                  forPlacementID:(NSString *)placementID
                            size:(CGSize)size
{
    NSError *bannerError = nil;
    
    if ([self isBannerAdAvailableForDelegate:delegate]) {
        BOOL success = [[VungleSDK sharedSDK] addAdViewToView:bannerView withOptions:options placementID:placementID adMarkup:[delegate getAdMarkup] error:&bannerError];
        
        if (success) {
            [self completeBannerAdViewForDelegate:delegate];
            // For a refresh banner delegate, if the Banner view is constructed successfully,
            // it will replace the old banner delegate.
            [self replaceOldBannerDelegateWithDelegate:delegate];
            return bannerView;
        }
    } else {
        bannerError = [NSError errorWithDomain:NSStringFromClass([self class]) code:8769 userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Ad not cached for placement %@", placementID]}];
    }
    
    MPLogError(@"Vungle: Banner loading error: %@", bannerError.localizedDescription);
    return nil;
}

- (void)completeBannerAdViewForDelegate:(id<VungleRouterDelegate>)delegate
{
    @synchronized (self) {
        NSString *placementID = [delegate getPlacementID];
        if (placementID.length > 0) {
            MPLogInfo(@"Vungle: Triggering a Banner ad completion call for %@", placementID);
            id<VungleRouterDelegate> bannerDelegate =
            [self getBannerDelegateWithPlacement:placementID
                                         eventID:[delegate getEventId]
                                 withBannerState:BannerRouterDelegateStatePlaying];
            if (bannerDelegate) {
                [[VungleSDK sharedSDK] finishDisplayingAd:placementID adMarkup:[bannerDelegate getAdMarkup]];
                bannerDelegate.bannerState = BannerRouterDelegateStateClosing;
            }
        }
    }
}

- (void)updateConsentStatus:(VungleConsentStatus)status
{
    [[VungleSDK sharedSDK] updateConsentStatus:status consentMessageVersion:@""];
}

- (VungleConsentStatus)getCurrentConsentStatus
{
    return [[VungleSDK sharedSDK] getCurrentConsentStatus];
}

- (void)clearDelegateForRequestingBanner
{
    __weak VungleRouter *weakself = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakself clearBannerDelegateWithState:BannerRouterDelegateStateRequesting];
    });
}

- (NSString *)parseEventId:(NSString *)adMarkup
{
    if (adMarkup.length > 0) {
        NSData *data = [adMarkup dataUsingEncoding:NSUTF8StringEncoding];
        id adMarkupDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return [adMarkupDict objectForKey:kVungleAdEventId];
    }
    return nil;
}

#pragma mark - private

- (BOOL)validateInfoData:(NSDictionary *)info
{
    BOOL isValid = YES;
    
    NSString *appId = [info objectForKey:kVungleAppIdKey];
    if ([appId length] == 0) {
        isValid = NO;
        MPLogInfo(@"Vungle: AppID is empty. Setup appID on MoPub dashboard.");
    } else {
        if (self.vungleAppID && ![self.vungleAppID isEqualToString:appId]) {
            isValid = NO;
            MPLogInfo(@"Vungle: AppID is different from the one used for initialization. Make sure you set the same network App ID for all AdUnits in this application on MoPub dashboard.");
        }
    }
    
    NSString *placementId = [info objectForKey:kVunglePlacementIdKey];
    if ([placementId length] == 0) {
        isValid = NO;
        MPLogInfo(@"Vungle: PlacementID is empty. Setup placementID on MoPub dashboard.");
    }
    
    if (isValid) {
        MPLogInfo(@"Vungle: Info data for the Ad Unit is valid.");
    }
    
    return isValid;
}

- (void)clearBannerDelegateWithState:(BannerRouterDelegateState)state
{
    @synchronized (self) {
        NSArray *array = [self.bannerDelegates.keyEnumerator allObjects];
        for (NSString *key in array) {
            if ([[self.bannerDelegates objectForKey:key] bannerState] == state) {
                [self.bannerDelegates removeObjectForKey:key];
            }
        }
        array = [self.hbBannerDelegates.keyEnumerator allObjects];
        for (NSString *key in array) {
            if ([[self.hbBannerDelegates objectForKey:key] bannerState] == state) {
                [self.hbBannerDelegates removeObjectForKey:key];
            }
        }
    }
}

- (void)cleanupFullScreenDelegate:(id<VungleRouterDelegate>)delegate
{
    @synchronized (self) {
        NSString *placementID = [delegate getPlacementID];
        NSString *eventID = [delegate getEventId];
        if (eventID.length > 0) {
            [self.hbDelegatesDict removeObjectForKey:eventID];
        } else if (placementID.length > 0) {
            [self.delegatesDict removeObjectForKey:placementID];
        }
    }
}

- (void)addToWaitingListWithDelegate:(id<VungleRouterDelegate>)delegate
{
    NSString *eventId = [delegate getEventId];
    if (eventId.length > 0) {
        if (![self.hbWaitingListDict objectForKey:eventId]) {
            [self.hbWaitingListDict setObject:delegate forKey:eventId];
        }
    } else {
        NSString *placementId = [delegate getPlacementID];
        if (![self.waitingListDict objectForKey:placementId]) {
            [self.waitingListDict setObject:delegate forKey:placementId];
        }
    }
}

- (void)clearWaitingList
{
    [self requestAdsInWaitingListDictionary:self.waitingListDict];
    [self requestAdsInWaitingListDictionary:self.hbWaitingListDict];
}

- (void)requestAdsInWaitingListDictionary:(NSMutableDictionary *)waitingListDict
{
    for (id key in waitingListDict) {
        id<VungleRouterDelegate> delegateInstance = [waitingListDict objectForKey:key];
        
        if ([delegateInstance respondsToSelector:@selector(getBannerSize)]) {
            [self requestBannerAdWithDelegate:delegateInstance];
        } else {
            [self requestAdWithCustomEventInfo:nil delegate:delegateInstance];
        }
    }

    [waitingListDict removeAllObjects];
}

- (void)requestBannerAdFailedWithError:(NSError *)error
                           placementID:(NSString *)placementID
                              delegate:(id<VungleRouterDelegate>)delegate
{
    if (error) {
        MPLogError(@"Vungle: Unable to load an ad for Placement ID :%@, Error %@", placementID, error);
    } else {
        NSString *errorMessage = [NSString stringWithFormat:@"Vungle: Unable to load an ad for Placement ID :%@.", placementID];
        error = [NSError errorWithCode:MOPUBErrorAdapterFailedToLoadAd
                  localizedDescription:errorMessage];
        MPLogError(@"%@", errorMessage);
    }

    [delegate vungleAdDidFailToLoad:error];
}

- (VungleAdSize)getVungleBannerAdSizeType:(CGSize)size
{
    if (CGSizeEqualToSize(size, kVNGBannerSize)) {
        return VungleAdSizeBanner;
    } else if (CGSizeEqualToSize(size, kVNGShortBannerSize)) {
        return VungleAdSizeBannerShort;
    } else if (CGSizeEqualToSize(size, kVNGLeaderboardBannerSize)) {
        return VungleAdSizeBannerLeaderboard;
    }
    
    return VungleAdSizeUnknown;
}

- (id<VungleRouterDelegate>)getDelegateWithPlacement:(NSString *)placementID
                                             eventID:(NSString *)eventID
                                     withBannerState:(BannerRouterDelegateState)state
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID
                                                                               eventID:eventID];
    if (!targetDelegate) {
        targetDelegate = [self getBannerDelegateWithPlacement:placementID eventID:eventID withBannerState:state];
    }
    
    return targetDelegate;
}

- (id<VungleRouterDelegate>)getFullScreenDelegateWithPlacement:(NSString *)placementID
                                                       eventID:(NSString *)eventID
{
    if (eventID.length > 0) {
        return [self.hbDelegatesDict objectForKey:eventID];
    }
    if (placementID.length) {
        return [self.delegatesDict objectForKey:placementID];
    }
    return nil;
}

- (id<VungleRouterDelegate>)getBannerDelegateWithPlacement:(NSString *)placementID
                                                   eventID:(NSString *)eventID
{
    if (eventID.length > 0) {
        return [self.hbBannerDelegates objectForKey:eventID];
    }
    if (placementID.length) {
        return [self.bannerDelegates objectForKey:placementID];
    }
    return nil;
}

- (id<VungleRouterDelegate>)getBannerDelegateWithPlacement:(NSString *)placementID
                                                   eventID:(NSString *)eventID
                                           withBannerState:(BannerRouterDelegateState)state
{
    id<VungleRouterDelegate> targetDelegate = [self getBannerDelegateWithPlacement:placementID eventID:eventID];
    if (targetDelegate.bannerState != state) {
        return nil;
    }

    return targetDelegate;
}

- (void)replaceOldBannerDelegateWithDelegate:(id<VungleRouterDelegate>)delegate
{
    @synchronized (self) {
        NSString *key = [delegate getEventId];
        NSMapTable<NSString *, id<VungleRouterDelegate>> *delegateTable;
        if (key.length > 0) {
            delegateTable = self.hbBannerDelegates;
        } else {
            key = [delegate getPlacementID];
            delegateTable = self.bannerDelegates;
        }
        id<VungleRouterDelegate> bannerDelegate = [self getBannerDelegateWithPlacement:[delegate getPlacementID] eventID:[delegate getEventId]];
        if (bannerDelegate != delegate) {
            [delegateTable setObject:delegate forKey:key];
        }
    }
}

#pragma mark - VungleSDKDelegate Methods

- (void) vungleSDKDidInitialize
{
    MPLogInfo(@"Vungle: the SDK has been initialized successfully.");
    self.sdkInitializeState = SDKInitializeStateInitialized;
    [self clearWaitingList];
}

- (void)vungleAdPlayabilityUpdate:(BOOL)isAdPlayable
                      placementID:(nullable NSString *)placementID
                            error:(nullable NSError *)error
{
    if (!placementID.length) {
        return;
    }
    [self vungleAdPlayabilityUpdate:isAdPlayable placementID:placementID eventID:nil error:error];
}

- (void)vungleAdPlayabilityUpdate:(BOOL)isAdPlayable
                          eventID:(nullable NSString *)eventID
                            error:(nullable NSError *)error
{
    if (!eventID.length) {
        return;
    }
    [self vungleAdPlayabilityUpdate:isAdPlayable placementID:nil eventID:eventID error:error];
}

- (void)vungleAdPlayabilityUpdate:(BOOL)isAdPlayable
                      placementID:(NSString *)placementID
                          eventID:(NSString *)eventID
                            error:(NSError *)error
{
    NSString *message = nil;
    NSError *playabilityError = nil;
    if (!isAdPlayable) {
        message = error ? [NSString stringWithFormat:@"Vungle: Ad playability update returned error for Placement ID: %@, Error: %@", placementID, error.localizedDescription] : [NSString stringWithFormat:@"Vungle: Ad playability update returned Ad is not playable for Placement ID: %@.", placementID];
        playabilityError = error ? : [NSError errorWithCode:MOPUBErrorAdapterFailedToLoadAd localizedDescription:message];
    }

    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID
                                                                               eventID:eventID];
    if (targetDelegate) {
        if (isAdPlayable) {
            MPLogInfo(@"Vungle: Ad playability update returned ad is playable for Placement ID: %@", placementID);
            [targetDelegate vungleAdDidLoad];
        } else {
            MPLogInfo(@"%@", message);
            if (!self.isAdPlaying) {
                [targetDelegate vungleAdDidFailToLoad:playabilityError];
            }
        }
    } else {
        @synchronized (self) {
            id<VungleRouterDelegate> bannerDelegate =
            [self getBannerDelegateWithPlacement:placementID
                                         eventID:eventID
                                 withBannerState:BannerRouterDelegateStateRequesting];
            if (bannerDelegate) {
                if (isAdPlayable) {
                    MPLogInfo(@"Vungle: Ad playability update returned ad is playable for Placement ID: %@", placementID);
                    [bannerDelegate vungleAdDidLoad];
                    bannerDelegate.bannerState = BannerRouterDelegateStateCached;
                } else {
                    MPLogInfo(@"%@", message);
                    [bannerDelegate vungleAdDidFailToLoad:playabilityError];
                    bannerDelegate.bannerState = BannerRouterDelegateStateClosed;
                    [self clearBannerDelegateWithState:BannerRouterDelegateStateClosed];
                }
            }
        }
    }
}

- (void)vungleWillShowAdForPlacementID:(nullable NSString *)placementID
{
    if (!placementID.length) {
        return;
    }
    [self vungleWillShowAdForPlacementID:placementID eventID:nil];
}

- (void)vungleWillShowAdForEventID:(nullable NSString *)eventID
{
    if (!eventID.length) {
        return;
    }
    [self vungleWillShowAdForPlacementID:nil eventID:eventID];
}

- (void)vungleWillShowAdForPlacementID:(NSString *)placementID
                               eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if (!targetDelegate) {
        @synchronized (self) {
            id<VungleRouterDelegate> bannerDelegate =
            [self getBannerDelegateWithPlacement:placementID
                                         eventID:eventID
                                 withBannerState:BannerRouterDelegateStateCached];
            if (bannerDelegate) {
                bannerDelegate.bannerState = BannerRouterDelegateStatePlaying;
            }
        }
    }

    if ([targetDelegate respondsToSelector:@selector(vungleAdWillAppear)]) {
        [targetDelegate vungleAdWillAppear];
    }
}

- (void)vungleDidShowAdForPlacementID:(nullable NSString *)placementID
{
    [self vungleDidShowAdForPlacementID:placementID eventID:nil];
}

- (void)vungleDidShowAdForEventID:(nullable NSString *)eventID
{
    [self vungleDidShowAdForPlacementID:nil eventID:eventID];
}

- (void)vungleDidShowAdForPlacementID:(NSString *)placementID
                              eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if ([targetDelegate respondsToSelector:@selector(vungleAdDidAppear)]) {
        [targetDelegate vungleAdDidAppear];
    }
}

- (void)vungleAdViewedForPlacement:(NSString *)placementID
{
    if (!placementID.length) {
        return;
    }
    [self vungleAdViewedForPlacement:placementID eventID:nil];
}

- (void)vungleAdViewedForAdUnit:(nullable NSString *)eventID
{
    if (!eventID.length) {
        return;
    }
    [self vungleAdViewedForPlacement:nil eventID:eventID];
}

- (void)vungleAdViewedForPlacement:(NSString *)placementID
                           eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if (!targetDelegate) {
        @synchronized (self) {
            targetDelegate =
            [self getBannerDelegateWithPlacement:placementID
                                         eventID:eventID
                                 withBannerState:BannerRouterDelegateStatePlaying];
        }
    }
    [targetDelegate vungleAdViewed];
}

- (void)vungleWillCloseAdForPlacementID:(nonnull NSString *)placementID
{
    [self vungleWillCloseAdForPlacementID:placementID eventID:nil];
}

- (void)vungleWillCloseAdForEventID:(nonnull NSString *)eventID
{
    [self vungleWillCloseAdForPlacementID:nil eventID:eventID];
}

- (void)vungleWillCloseAdForPlacementID:(NSString *)placementID
                                eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if ([targetDelegate respondsToSelector:@selector(vungleAdWillDisappear)]) {
        [targetDelegate vungleAdWillDisappear];
        self.isAdPlaying = NO;
    }
}

- (void)vungleDidCloseAdForPlacementID:(nonnull NSString *)placementID
{
    if (!placementID.length) {
        return;
    }
    [self vungleDidCloseAdForPlacementID:placementID eventID:nil];
}

- (void)vungleDidCloseAdForEventID:(nonnull NSString *)eventID
{
    if (!eventID.length) {
        return;
    }
    [self vungleDidCloseAdForPlacementID:nil eventID:eventID];
}

- (void)vungleDidCloseAdForPlacementID:(NSString *)placementID
                               eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if (!targetDelegate) {
        @synchronized (self) {
            id<VungleRouterDelegate> bannerDelegate =
            [self getBannerDelegateWithPlacement:placementID
                                         eventID:eventID
                                 withBannerState:BannerRouterDelegateStateClosing];
            if (bannerDelegate) {
                bannerDelegate.bannerState = BannerRouterDelegateStateClosed;
                [self clearBannerDelegateWithState:BannerRouterDelegateStateClosed];
            }
        }
    }

    if ([targetDelegate respondsToSelector:@selector(vungleAdDidDisappear)]) {
        [targetDelegate vungleAdDidDisappear];
    }
}

- (void)vungleTrackClickForPlacementID:(nullable NSString *)placementID
{
    if (!placementID.length) {
        return;
    }
    [self vungleTrackClickForPlacementID:placementID eventID:nil];
}

- (void)vungleTrackClickForEventID:(nullable NSString *)eventID
{
    if (!eventID.length) {
        return;
    }
    [self vungleTrackClickForPlacementID:nil eventID:eventID];
}

- (void)vungleTrackClickForPlacementID:(NSString *)placementID
                               eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getDelegateWithPlacement:placementID
                                                                     eventID:eventID
                                                             withBannerState:BannerRouterDelegateStatePlaying];
    [targetDelegate vungleAdTrackClick];
}

- (void)vungleRewardUserForPlacementID:(nullable NSString *)placementID
{
    [self vungleRewardUserForPlacementID:placementID eventID:nil];
}

- (void)vungleRewardUserForEventID:(nullable NSString *)eventID
{
    [self vungleRewardUserForPlacementID:nil eventID:eventID];
}

- (void)vungleRewardUserForPlacementID:(NSString *)placementID
                               eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getFullScreenDelegateWithPlacement:placementID eventID:eventID];
    if ([targetDelegate respondsToSelector:@selector(vungleAdRewardUser)]) {
        [targetDelegate vungleAdRewardUser];
    }
}

- (void)vungleWillLeaveApplicationForPlacementID:(nullable NSString *)placementID
{
    [self vungleWillLeaveApplicationForPlacementID:placementID eventID:nil];
}

- (void)vungleWillLeaveApplicationForEventID:(nullable NSString *)eventID
{
    [self vungleWillLeaveApplicationForPlacementID:nil eventID:eventID];
}

- (void)vungleWillLeaveApplicationForPlacementID:(NSString *)placementID
                                         eventID:(NSString *)eventID
{
    id<VungleRouterDelegate> targetDelegate = [self getDelegateWithPlacement:placementID
                                                                     eventID:eventID
                                                             withBannerState:BannerRouterDelegateStatePlaying];
    [targetDelegate vungleAdWillLeaveApplication];
}

#pragma mark - VungleSDKNativeAds delegate methods

- (void)nativeAdsPlacementDidLoadAd:(NSString *)placement
{
    // Ad loaded successfully. We allow the playability update to notify the
    // Banner Custom Event class of successful ad loading.
}

- (void)nativeAdsPlacement:(NSString *)placement didFailToLoadAdWithError:(NSError *)error
{
    // Ad failed to load. We allow the playability update to notify the
    // Banner Custom Event class of unsuccessful ad loading.
}

- (void)nativeAdsPlacementWillTriggerURLLaunch:(NSString *)placement
{
    [[self.delegatesDict objectForKey:placement] vungleAdWillLeaveApplication];
}

@end
