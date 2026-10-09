#import <Foundation/Foundation.h>
typedef NS_ENUM(NSUInteger, TBOption) {
    TBHideShopTab, TBHideShopPosts, TBHideAds, TBHideSponsored,
    TBHideLive, TBHidePromotional, TBHideUnavailable, TBOptionCount
};
#ifdef __cplusplus
extern "C" {
#endif
extern unsigned int TBEnabledOptions;
static inline BOOL TBOptionEnabled(TBOption option) {
    return (__atomic_load_n(&TBEnabledOptions,__ATOMIC_RELAXED) & (1u << option)) != 0;
}
void TBLoadPreferences(void);
void TBSetOption(TBOption option, BOOL enabled);
NSString *TBOptionTitle(TBOption option);
void TBReport(NSString *message);

#ifdef __cplusplus
}
#endif
