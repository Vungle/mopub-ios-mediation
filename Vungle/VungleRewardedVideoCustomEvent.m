//
//  VungleRewardedVideoCustomEvent.m
//  MoPubSDK
//
//  Copyright (c) 2015 MoPub. All rights reserved.
//

#import <VungleSDK/VungleSDK.h>
#if __has_include("MoPub.h")
    #import "MPError.h"
    #import "MPLogging.h"
    #import "MoPub.h"
    #import "MPRewardedVideoError.h"
    #import "MPRewardedVideoReward.h"
#endif
#import "VungleAdapterConfiguration.h"
#import "VungleInstanceMediationSettings.h"
#import "VungleRewardedVideoCustomEvent.h"
#import "VungleRouter.h"

@interface VungleRewardedVideoCustomEvent ()  <VungleRouterDelegate>

@property (nonatomic, copy) NSString *placementId;

@end

@implementation VungleRewardedVideoCustomEvent


- (void)initializeSdkWithParameters:(NSDictionary *)parameters
{
    [[VungleRouter sharedRouter] initializeSdkWithInfo:parameters];
}

- (void)requestRewardedVideoWithCustomEventInfo:(NSDictionary *)info adMarkup:(NSString *)adMarkup
{
    self.placementId = [info objectForKey:kVunglePlacementIdKey];

    // Cache the initialization parameters
    [VungleAdapterConfiguration updateInitializationParameters:info];

    MPLogAdEvent([MPLogEvent adLoadAttemptForAdapter:NSStringFromClass(self.class) dspCreativeId:nil dspName:nil], self.placementId);
    [[VungleRouter sharedRouter] requestRewardedVideoAdWithCustomEventInfo:info delegate:self];
}

- (BOOL)hasAdAvailable
{
    return [[VungleSDK sharedSDK] isAdCachedForPlacementID:self.placementId];
}

- (void)presentRewardedVideoFromViewController:(UIViewController *)viewController
{
    MPLogAdEvent([MPLogEvent adShowAttemptForAdapter:NSStringFromClass(self.class)], self.placementId);
    if ([[VungleRouter sharedRouter] isAdAvailableForPlacementId:self.placementId]) {
        VungleInstanceMediationSettings *settings = [self.delegate instanceMediationSettingsForClass:[VungleInstanceMediationSettings class]];

        NSString *customerId = [self.delegate customerIdForRewardedVideoCustomEvent:self];
        [[VungleRouter sharedRouter] presentRewardedVideoAdFromViewController:viewController customerId:customerId settings:settings forPlacementId:self.placementId];
    } else {
        NSError *error = [NSError errorWithCode:MPRewardedVideoAdErrorNoAdsAvailable localizedDescription:@"Failed to show Vungle rewarded video: Vungle now claims that there is no available video ad."];
        MPLogAdEvent([MPLogEvent adShowFailedForAdapter:NSStringFromClass(self.class) error:error], [self getPlacementID]);
        [self.delegate rewardedVideoDidFailToPlayForCustomEvent:self error:error];
    }
}

- (void)handleCustomEventInvalidated
{
    [[VungleRouter sharedRouter] clearDelegateForPlacementId:self.placementId];
}

- (void)handleAdPlayedForCustomEventNetwork
{
    //empty implementation
}

#pragma mark - MPVungleDelegate

- (void)vungleAdDidLoad
{
    MPLogAdEvent([MPLogEvent adLoadSuccessForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoDidLoadAdForCustomEvent:self];
}

- (void)vungleAdWillAppear
{
    MPLogAdEvent([MPLogEvent adWillAppearForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoWillAppearForCustomEvent:self];
}

- (void)vungleAdDidAppear
{
    MPLogAdEvent([MPLogEvent adShowSuccessForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    MPLogAdEvent([MPLogEvent adDidAppearForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoDidAppearForCustomEvent:self];
}

- (void)vungleAdWillDisappear
{
    MPLogAdEvent([MPLogEvent adWillDisappearForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoWillDisappearForCustomEvent:self];
}

- (void)vungleAdDidDisappear
{
    MPLogAdEvent([MPLogEvent adDidDisappearForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoDidDisappearForCustomEvent:self];
}

- (void)vungleAdTrackClick
{
    MPLogAdEvent([MPLogEvent adTappedForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoDidReceiveTapEventForCustomEvent:self];
}

- (void)vungleAdRewardUser
{
    [self performSelectorOnMainThread:@selector(rewardUser) withObject:nil waitUntilDone:NO];
}

- (void)vungleAdWillLeaveApplication
{
    MPLogAdEvent([MPLogEvent adWillLeaveApplicationForAdapter:NSStringFromClass(self.class)], [self getPlacementID]);
    [self.delegate rewardedVideoWillLeaveApplicationForCustomEvent:self];
}

- (void)vungleAdDidFailToLoad:(NSError *)error
{
    MPLogAdEvent([MPLogEvent adLoadFailedForAdapter:NSStringFromClass(self.class) error:error], [self getPlacementID]);
    [self.delegate rewardedVideoDidFailToLoadAdForCustomEvent:self error:error];
}

- (void)vungleAdDidFailToPlay:(NSError *)error
{
    MPLogAdEvent([MPLogEvent adShowFailedForAdapter:NSStringFromClass(self.class) error:error], [self getPlacementID]);
    [self.delegate rewardedVideoDidFailToPlayForCustomEvent:self error:error];
}

- (NSString *)getPlacementID
{
    return self.placementId;
}

- (void)rewardUser
{
    MPRewardedVideoReward *reward = [[MPRewardedVideoReward alloc] initWithCurrencyAmount:@(kMPRewardedVideoRewardCurrencyAmountUnspecified)];
    MPLogAdEvent([MPLogEvent adShouldRewardUserWithReward:reward], [self getPlacementID]);
    [self.delegate rewardedVideoShouldRewardUserForCustomEvent:self reward:reward];
}

@end
