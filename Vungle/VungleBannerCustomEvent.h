//
//  VungleBannerCustomEvent.h
//  VungleMoPubAdapter
//
//  Created by Clarke Bishop on 9/24/18.
//  Copyright © 2018 Vungle. All rights reserved.
//

#if __has_include(<MoPub/MoPub.h>)
#import <MoPub/MoPub.h>
#elif __has_include(<MoPubSDKFramework/MoPub.h>)
#import <MoPubSDKFramework/MoPub.h>
#else
#import "MPBannerCustomEvent.h"
#endif

@interface VungleBannerCustomEvent : MPBannerCustomEvent

@end

