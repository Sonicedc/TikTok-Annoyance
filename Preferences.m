#import "Preferences.h"
unsigned int TBEnabledOptions = (1u << TBOptionCount)-1;
static NSString *Key(TBOption option) { return [@"TikTokAnnoyance." stringByAppendingString:@[@"HideShopTab",@"HideShopPosts",@"HideAds",@"HideSponsored",@"HideLive",@"HidePromotional",@"HideUnavailable"][option]]; }
void TBLoadPreferences(void) {
    unsigned int mask=0;
    for(NSUInteger i=0;i<TBOptionCount;i++) {
        id saved=[NSUserDefaults.standardUserDefaults objectForKey:Key(i)];
        if (!saved || [saved boolValue]) mask |= 1u << i;
    }
    __atomic_store_n(&TBEnabledOptions,mask,__ATOMIC_RELAXED);
}
void TBSetOption(TBOption option, BOOL enabled) {
    if (option >= TBOptionCount) return;
    if (enabled) __atomic_fetch_or(&TBEnabledOptions,1u << option,__ATOMIC_RELAXED);
    else __atomic_fetch_and(&TBEnabledOptions,~(1u << option),__ATOMIC_RELAXED);
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:Key(option)];
}
NSString *TBOptionTitle(TBOption option) {
    return @[@"Hide Shop tab",@"Shop attachment posts",@"Ads",@"Sponsored posts",@"LIVE streams",@"Promotional content",@"Unavailable videos"][option];
}
