#import <Foundation/Foundation.h>
@interface AWEAwemeModel : NSObject
@property BOOL isAds, isSoftAds, hasAd, isLive, isLiveHighlightCard, isLivePlaybackPlaceholder, isAuthorLive, hasProductsOfVSA, nativeProduct;
@property NSArray *productInfo, *i18nAnchors, *brandedContentAccounts;
@property id feedProductSelectionCardProductInfoModel, anchorInfo, commerceModel, promoteTagInfo, status;
@end
@implementation AWEAwemeModel
@end
@interface Fixture : NSObject
@property NSString *schema, *mostRelevantProductId, *tabID, *topTabKey;
@property BOOL brandedContentType, brandedOrganicType, hasTaggedBA, isPromoteAdLabel, ec_isExpandProductAnchor, deleted, isProhibited;
@property NSInteger type;
@property id extraDic, extraArray, extra;
@end
@implementation Fixture
@end
@interface ResponseFixture : NSObject
@property NSArray *awemeList, *liveList;
@property BOOL hasMore;
@property NSNumber *cursor;
@end
@implementation ResponseFixture
@end
@interface TTKECSearchVideoProductAnchorView : NSObject
+ (BOOL)hasProductAnchorWithAwemeModel:(AWEAwemeModel *)post;
@end
@implementation TTKECSearchVideoProductAnchorView
+ (BOOL)hasProductAnchorWithAwemeModel:(AWEAwemeModel *)post { return post.nativeProduct; }
@end
int main(void) { @autoreleasepool {
    AWEAwemeModel *normal=[AWEAwemeModel new]; normal.isAuthorLive=YES;
    NSCAssert(BlockReason(normal)==nil,@"An author being live must not remove their ordinary video");
    AWEAwemeModel *ad=[AWEAwemeModel new]; ad.isAds=YES;
    AWEAwemeModel *live=[AWEAwemeModel new]; live.isLive=YES;
    AWEAwemeModel *shop=[AWEAwemeModel new]; shop.productInfo=@[@"product"];
    AWEAwemeModel *anchorPost=[AWEAwemeModel new]; Fixture *anchor=[Fixture new]; anchor.schema=@"sslocal://ec/pdp?product_id=1"; anchorPost.i18nAnchors=@[anchor];
    AWEAwemeModel *brand=[AWEAwemeModel new]; Fixture *commerce=[Fixture new]; commerce.brandedContentType=YES; brand.commerceModel=commerce;
    AWEAwemeModel *promoted=[AWEAwemeModel new]; Fixture *tag=[Fixture new]; tag.isPromoteAdLabel=YES; promoted.promoteTagInfo=tag;
    NSCAssert([BlockReason(ad) isEqual:@"ad"] && [BlockReason(live) isEqual:@"live"] && [BlockReason(shop) isEqual:@"shop"] && [BlockReason(anchorPost) isEqual:@"shop"] && [BlockReason(brand) isEqual:@"branded"] && [BlockReason(promoted) isEqual:@"promoted"],@"Blocked categories");
    NSArray *mixed=@[ad,normal,live,shop,normal,anchorPost,brand,promoted];
    NSCAssert(([FilterPosts(mixed) isEqual:@[normal,normal]]),@"Keep order and duplicates; remove queue entries");
    NSCAssert(FilterPosts(@[ad,live,shop]).count==0,@"Fully blocked batch must be empty");
    NSArray *safe=@[normal]; NSCAssert(FilterPosts(safe)==safe,@"Unchanged batches retain identity");
    NSCAssert(FilterPosts(nil)==nil,@"Nil batch");
    Fixture *generic=[Fixture new]; generic.schema=@"sslocal://music/detail/123"; normal.i18nAnchors=@[generic];
    NSCAssert(BlockReason(normal)==nil,@"Music anchors must remain");
    Fixture *shopTab=[Fixture new]; shopTab.tabID=@"shop"; Fixture *fyp=[Fixture new]; fyp.tabID=@"homepage_hot";
    NSCAssert([FilterTabs(@[shopTab,fyp]) isEqual:@[fyp]],@"Shop tab removal preserves For You");
    NSIndexSet *indexes=[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2,4)]; NSArray *posts=@[ad,normal,shop,normal];
    NSMutableIndexSet *positions=[NSMutableIndexSet indexSet]; __block NSUInteger item=0,removed=0;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index,BOOL *stop){if(BlockReason(posts[item++]))removed++;else [positions addIndex:index-removed];}];
    NSCAssert([positions isEqual:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2,2)]],@"Batch insertion indexes shift with removed entries");
    AWEAwemeModel *deleted=[AWEAwemeModel new]; Fixture *status=[Fixture new]; status.deleted=YES; deleted.status=status;
    NSCAssert([BlockReason(deleted) isEqual:@"unavailable"],@"Confirmed deleted posts must never occupy a queue slot");
    ResponseFixture *response=[ResponseFixture new]; response.awemeList=@[normal,ad,deleted,normal,live]; response.liveList=@[live]; response.hasMore=YES; response.cursor=@42;
    FilterResponse(response);
    // Simulate TikTok constructing its queue, insert count and indexes from the response.
    NSArray *nativeQueue=[response.awemeList copy]; NSMutableArray *nativeIndexes=[NSMutableArray array];
    for(NSUInteger i=0;i<response.awemeList.count;i++) [nativeIndexes addObject:@(i)];
    NSCAssert(nativeQueue.count==2 && nativeIndexes.count==2 && [nativeIndexes.lastObject isEqual:@1],@"Response is compact before native queue/index construction: no placeholder slots");
    NSCAssert(response.liveList.count==0 && response.hasMore && [response.cursor isEqual:@42],@"Auxiliary live previews removed; pagination preserved");
    FilterResponse(response); NSCAssert(response.awemeList.count==2,@"Repeated response filtering is idempotent");
    AWEAwemeModel *sponsored=[AWEAwemeModel new]; sponsored.isSoftAds=YES; sponsored.hasAd=YES;
    NSCAssert([BlockReason(sponsored) isEqual:@"sponsored"],@"Sponsored category detected independently");
    NSArray *fixtures=@[shop,ad,sponsored,live,brand,deleted];
    NSArray *options=@[@(TBHideShopPosts),@(TBHideAds),@(TBHideSponsored),@(TBHideLive),@(TBHidePromotional),@(TBHideUnavailable)];
    unsigned int all=(1u<<TBOptionCount)-1;
    for(NSUInteger i=0;i<fixtures.count;i++) {
        __atomic_store_n(&TBEnabledOptions,all & ~(1u << [options[i] unsignedIntValue]),__ATOMIC_RELAXED);
        NSCAssert(BlockReason(fixtures[i])==nil,@"Disabled filter must preserve its own post category");
        NSCAssert(TBOptionEnabled(TBHideShopTab),@"Toggling a post filter must not change the Shop-tab switch");
    }
    __atomic_store_n(&TBEnabledOptions,0,__ATOMIC_RELAXED);
    NSCAssert(FilterPosts(mixed)==mixed,@"All switches off preserve the complete batch");
    NSCAssert(FilterTabs(@[shopTab,fyp]).count==2,@"Shop-tab switch off preserves Shop");
    response.awemeList=mixed; response.liveList=@[live]; FilterResponse(response);
    NSCAssert(response.awemeList==mixed && response.liveList.count==1,@"Disabled filters preserve response and auxiliary live list");
    __atomic_store_n(&TBEnabledOptions,all,__ATOMIC_RELAXED);
    AWEAwemeModel *payloadPost=[AWEAwemeModel new]; Fixture *payloadAnchor=[Fixture new]; payloadAnchor.extra=@"{\"items\":[{\"product_id\":\"123\"}]}"; payloadPost.i18nAnchors=@[payloadAnchor];
    NSCAssert([BlockReason(payloadPost) isEqual:@"shop-payload"],@"Shop JSON attachment without a URL or productInfo must be removed");
    payloadAnchor.extra=@"{\"effect_id\":\"123\",\"name\":\"Tummy Hurts Kneeling Knight\"}";
    NSCAssert(BlockReason(payloadPost)==nil,@"Product-name text alone must not remove an ordinary effect anchor");
    payloadAnchor.extra=nil; payloadAnchor.type=35;
    NSCAssert([BlockReason(payloadPost) isEqual:@"shop-anchor"],@"Verified Shop-store anchor type");
    AWEAwemeModel *nativeShop=[AWEAwemeModel new]; nativeShop.nativeProduct=YES;
    NSCAssert([BlockReason(nativeShop) isEqual:@"shop-native"],@"Native product predicate covers app-supported representations");
    __atomic_store_n(&TBEnabledOptions,all & ~(1u<<TBHideShopPosts),__ATOMIC_RELAXED);
    NSCAssert(BlockReason(payloadPost)==nil && BlockReason(nativeShop)==nil,@"Expanded Shop detection obeys the Shop-post switch");
    __atomic_store_n(&TBEnabledOptions,all,__ATOMIC_RELAXED);
    puts("PASS: ads, live, Shop, anchors, branded/promoted content, ordinary posts, order, empty batches, tabs, insertion indexes and independent filter switches");
} return 0; }
