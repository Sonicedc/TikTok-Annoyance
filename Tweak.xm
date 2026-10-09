#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "Preferences.h"

// Bounded, app-local diagnostics; never records post IDs or captions.
static void TBLog(NSString *format, ...) {
    va_list args; va_start(args,format);
    NSString *line=[[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    NSLog(@"[TikTokBlocker] %@",line);
    @synchronized (NSProcessInfo.processInfo) {
        NSString *cache=NSSearchPathForDirectoriesInDomains(NSCachesDirectory,NSUserDomainMask,YES).firstObject;
        NSString *path=[cache stringByAppendingPathComponent:@"TikTokBlocker.log"];
        NSData *data=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        NSFileManager *fm=NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:path] || [[fm attributesOfItemAtPath:path error:nil] fileSize] > 131072) [data writeToFile:path atomically:YES];
        else { NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path]; [file seekToEndOfFile]; [file writeData:data]; [file closeFile]; }
    }
}

void TBReport(NSString *message) { TBLog(@"%@",message); }

// All hook signatures verified against the supplied 47.1.0 (471044) IPA.
// Only metadata is inspected; captions, account information and post IDs are not logged.
static id Read(id object, NSString *name) {
    if (!object) return nil;
    SEL sel = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], sel);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char type[128]; method_getReturnType(method, type, sizeof(type));
    if (type[0] == '@') return ((id (*)(id, SEL))objc_msgSend)(object, sel);
    if (type[0] == 'B') return @(((BOOL (*)(id, SEL))objc_msgSend)(object, sel));
    if (type[0] == 'q') return @(((long long (*)(id, SEL))objc_msgSend)(object, sel));
    if (type[0] == 'Q') return @(((unsigned long long (*)(id, SEL))objc_msgSend)(object, sel));
    return nil;
}
static BOOL Truth(id object, NSString *name) { id v=Read(object,name); return [v isKindOfClass:NSNumber.class] && [v boolValue]; }
static BOOL Present(id value) {
    if (!value || value == NSNull.null) return NO;
    if ([value isKindOfClass:NSString.class]) return [value length] && ![value isEqual:@"0"];
    if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) return [value count] > 0;
    if ([value isKindOfClass:NSNumber.class]) return [value longLongValue] != 0;
    return YES;
}
static BOOL ShopLink(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *s=[value lowercaseString];
    for (NSString *marker in @[@"ec/pdp", @"ec/shop", @"ecommerce", @"/product_detail", @"/view/product/"])
        if ([s containsString:marker]) return YES;
    return NO;
}
// Product attachments can carry their payload in anchor.extra instead of URLs.
// Inspect only structured attachment data, never captions or product-name keywords.
static BOOL ProductPayload(id value, NSUInteger depth) {
    if (!value || depth>5) return NO;
    if ([value isKindOfClass:NSString.class]) {
        NSString *text=value;
        if (text.length>262144 || (! [text hasPrefix:@"{"] && ![text hasPrefix:@"["])) return NO;
        id parsed=[NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];
        return ProductPayload(parsed,depth+1);
    }
    if ([value isKindOfClass:NSArray.class]) {
        for(id item in value) if(ProductPayload(item,depth+1)) return YES;
    } else if ([value isKindOfClass:NSDictionary.class]) {
        for(id key in value) {
            id payload=value[key];
            if ([key isKindOfClass:NSString.class]) {
                NSString *normalized=[[key lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@""];
                if ([@[@"productid",@"productids",@"productlist",@"products",@"commodityid",@"commodityids"] containsObject:normalized] && Present(payload)) return YES;
            }
            if (ProductPayload(payload,depth+1)) return YES;
        }
    }
    return NO;
}
static BOOL NativeProductAnchor(id post) {
    Class cls=NSClassFromString(@"TTKECSearchVideoProductAnchorView");
    SEL sel=NSSelectorFromString(@"hasProductAnchorWithAwemeModel:");
    Method method=class_getClassMethod(cls,sel);
    // Verified + method in 471044; it checks attachment models, not video text.
    if (!method || strcmp(method_getTypeEncoding(method),"B24@0:8@16")) return NO;
    return ((BOOL (*)(id,SEL,id))objc_msgSend)(cls,sel,post);
}
static NSString *BlockReason(id post) {
    Class cls=NSClassFromString(@"AWEAwemeModel");
    if (!cls || ![post isKindOfClass:cls]) return nil;
    id status=Read(post,@"status");
    if (TBOptionEnabled(TBHideUnavailable) && (Truth(status,@"deleted") || Truth(status,@"isProhibited"))) return @"unavailable";
    id adLabel=Read(Read(Read(post,@"originAdInfo"),@"label"),@"text");
    BOOL sponsored=Truth(post,@"isSoftAds") || ([adLabel isKindOfClass:NSString.class] && [[adLabel lowercaseString] containsString:@"sponsored"]);
    if (sponsored) { if (TBOptionEnabled(TBHideSponsored)) return @"sponsored"; }
    else if (TBOptionEnabled(TBHideAds) && (Truth(post,@"isAds") || Truth(post,@"hasAd"))) return @"ad";
    if (TBOptionEnabled(TBHideLive) && (Truth(post,@"isLive") || Truth(post,@"isLiveHighlightCard") || Truth(post,@"isLivePlaybackPlaceholder"))) return @"live";
    if (TBOptionEnabled(TBHideShopPosts) && (Present(Read(post,@"productInfo")) || Truth(post,@"hasProductsOfVSA") || Present(Read(post,@"feedProductSelectionCardProductInfoModel")))) return @"shop";
    if (TBOptionEnabled(TBHideShopPosts) && NativeProductAnchor(post)) return @"shop-native";
    id anchors=Read(post,@"i18nAnchors");
    if (TBOptionEnabled(TBHideShopPosts) && [anchors isKindOfClass:NSArray.class]) for (id anchor in anchors) {
        // +generateShopAnchorModelWithAwemeModel: selects type 35 in this IPA.
        id type=Read(anchor,@"type");
        if ([type isKindOfClass:NSNumber.class] && [type integerValue]==35) return @"shop-anchor";
        if (ProductPayload(Read(anchor,@"extraDic"),0) || ProductPayload(Read(anchor,@"extraArray"),0) || ProductPayload(Read(anchor,@"extra"),0)) return @"shop-payload";
        if (Present(Read(anchor,@"mostRelevantProductId")) || Truth(anchor,@"ec_isExpandProductAnchor")) return @"shop";
        for (NSString *key in @[@"schema", @"url", @"deepLink", @"universalLink"])
            if (ShopLink(Read(anchor,key))) return @"shop";
    }
    id info=Read(post,@"anchorInfo");
    if (TBOptionEnabled(TBHideShopPosts) && ProductPayload(Read(info,@"extraDict"),0)) return @"shop-payload";
    if (TBOptionEnabled(TBHideShopPosts) && (ShopLink(Read(info,@"openURL")) || ShopLink(Read(info,@"webURL")))) return @"shop";
    id commerce=Read(post,@"commerceModel");
    if (TBOptionEnabled(TBHidePromotional) && (Truth(commerce,@"brandedContentType") || Truth(commerce,@"brandedOrganicType") || Truth(commerce,@"hasTaggedBA") || Present(Read(post,@"brandedContentAccounts")))) return @"branded";
    if (TBOptionEnabled(TBHideAds) && Truth(Read(post,@"promoteTagInfo"),@"isPromoteAdLabel")) return @"promoted";
    return nil;
}
static NSArray *FilterPosts(NSArray *posts) {
    if (![posts isKindOfClass:NSArray.class]) return posts;
    NSMutableArray *result=nil;
    NSUInteger i=0, removed=0;
    NSMutableDictionary *reasons=[NSMutableDictionary dictionary];
    for (id post in posts) {
        NSString *reason=BlockReason(post);
        if (reason) {
            if (!result) result=[[posts subarrayWithRange:NSMakeRange(0,i)] mutableCopy];
            removed++;
            reasons[reason]=@([reasons[reason] unsignedIntegerValue]+1);
        } else if (result) [result addObject:post];
        i++;
    }
    TBLog(@"batch: removed %lu of %lu queued posts; reasons=%@", (unsigned long)removed,(unsigned long)posts.count,reasons);
    return result ? [result copy] : posts;
}
// Run before TikTok builds transformed models, insert ranges and playback maps.
static void FilterResponse(id response) {
    Method setter=class_getInstanceMethod([response class],@selector(setAwemeList:));
    if (!setter || strcmp(method_getTypeEncoding(setter),"v24@0:8@16")) return;
    NSArray *posts=Read(response,@"awemeList");
    NSArray *filtered=FilterPosts(posts);
    if (filtered != posts) ((void (*)(id,SEL,id))objc_msgSend)(response,@selector(setAwemeList:),filtered);
    // This is a separate source of live previews merged into the For You batch.
    Method liveSetter=class_getInstanceMethod([response class],NSSelectorFromString(@"setLiveList:"));
    if (TBOptionEnabled(TBHideLive) && liveSetter && !strcmp(method_getTypeEncoding(liveSetter),"v24@0:8@16") && Present(Read(response,@"liveList"))) {
        ((void (*)(id,SEL,id))objc_msgSend)(response,NSSelectorFromString(@"setLiveList:"),@[]);
        TBLog(@"removed auxiliary live preview list before response processing");
    }
}
static BOOL FYPController(id controller) {
    Class smart=NSClassFromString(@"AWESmartFeedDataController");
    Class hot=NSClassFromString(@"AWEHotListDataController");
    // TTKFeedDataOperator.p_isFYPType is awemeType == 0 in this build.
    id type=Read(controller,@"type");
    return ((smart && [controller isKindOfClass:smart]) || (hot && [controller isKindOfClass:hot])) && [type isKindOfClass:NSNumber.class] && [type integerValue] == 0;
}
static BOOL FYPOperator(id object) { return Truth(object,@"p_isFYPType"); }
static BOOL ShopTab(id tab) {
    for (NSString *key in @[@"tabID", @"topTabKey"]) {
        id value=Read(tab,key);
        if ([value isKindOfClass:NSString.class]) {
            NSString *s=[value lowercaseString];
            if ([s containsString:@"shop"] || [s containsString:@"mall"] || [s containsString:@"ecommerce"]) return YES;
        }
    }
    id title=Read(Read(Read(tab,@"uiConfig"),@"itemView"),@"title");
    return [title isKindOfClass:NSString.class] && [title caseInsensitiveCompare:@"Shop"] == NSOrderedSame;
}
static NSArray *FilterTabs(NSArray *tabs) {
    if (!TBOptionEnabled(TBHideShopTab)) return tabs;
    if (![tabs isKindOfClass:NSArray.class]) return tabs;
    NSMutableArray *result=[NSMutableArray arrayWithCapacity:tabs.count];
    for (id tab in tabs) if (!ShopTab(tab)) [result addObject:tab];
    if (result.count != tabs.count) TBLog(@"removed Shop tab");
    return result.count == tabs.count ? tabs : [result copy];
}

%group HotQueue
%hook AWEHotListDataController
- (void)handleResponseModel:(id)response pullSuccess:(BOOL)success {
    if (FYPController(self)) FilterResponse(response);
    %orig;
}
- (void)handleResponseModel:(id)response pullType:(NSInteger)pullType pullSuccess:(BOOL)success {
    if (FYPController(self)) FilterResponse(response);
    %orig;
}
- (id)_loadmoreDataSourceWithArray:(NSArray *)array requestId:(id)requestID {
    return %orig(FYPController(self) ? FilterPosts(array) : array,requestID);
}
- (id)_refreshDataSourceWithArray:(NSArray *)array cleanRefresh:(BOOL)clean requestId:(id)requestID {
    return %orig(FYPController(self) ? FilterPosts(array) : array,clean,requestID);
}
- (id)awe_refreshDataSourceWithArray:(NSArray *)array cleanRefresh:(BOOL)clean requestId:(id)requestID {
    return %orig(FYPController(self) ? FilterPosts(array) : array,clean,requestID);
}
- (id)transferAwemeListIfNeededWithArray:(NSArray *)array {
    return %orig(FYPController(self) ? FilterPosts(array) : array);
}
- (id)transferAwemeListIfNeededWithArray:(NSArray *)array pullType:(NSInteger)pullType {
    return %orig(FYPController(self) ? FilterPosts(array) : array,pullType);
}
// Leave setDataSource: intact: callers and the backing queue must receive
// the same batch and count, including TikTok's item-ID/index-map updates.
%end
%end

%group Queue
%hook TTKFeedBaseDataController
- (id)_loadmoreDataSourceWithArray:(NSArray *)array requestId:(id)requestID {
    return %orig(FYPController(self) ? FilterPosts(array) : array, requestID);
}
- (id)_refreshDataSourceWithArray:(NSArray *)array cleanRefresh:(BOOL)clean requestId:(id)requestID {
    return %orig(FYPController(self) ? FilterPosts(array) : array, clean, requestID);
}
%end
%hook TTKFeedDataOperator
- (void)updateDataSource:(NSArray *)array param:(id)param {
    %orig(FYPOperator(self) ? FilterPosts(array) : array, param);
}
- (void)addObject:(id)post param:(id)param {
    if (FYPOperator(self) && BlockReason(post)) return;
    %orig;
}
- (NSInteger)insertObject:(id)post atIndex:(NSInteger)index param:(id)param {
    if (FYPOperator(self) && BlockReason(post)) return NSNotFound;
    return %orig;
}
- (BOOL)insertAweme:(id)post atIndex:(NSInteger)index checkAndRemove:(BOOL)check checkStartPosition:(NSInteger)start param:(id)param {
    if (FYPOperator(self) && BlockReason(post)) return NO;
    return %orig;
}
- (void)insertObjects:(NSArray *)posts atIndexes:(NSIndexSet *)indexes param:(id)param {
    if (!FYPOperator(self) || ![posts isKindOfClass:NSArray.class] || ![indexes isKindOfClass:NSIndexSet.class] || posts.count != indexes.count) { %orig; return; }
    NSMutableArray *kept=[NSMutableArray array]; NSMutableIndexSet *positions=[NSMutableIndexSet indexSet];
    __block NSUInteger item=0, removed=0;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
        id post=posts[item++];
        if (BlockReason(post)) { removed++; return; }
        [kept addObject:post]; [positions addIndex:index-removed];
    }];
    if (kept.count) %orig(kept, positions, param);
}
%end
%end

%group Tabs
%hook TTKTabEntranceResult
- (NSArray *)topTabs { return FilterTabs(%orig); }
- (void)setTopTabs:(NSArray *)tabs { %orig(FilterTabs(tabs)); }
%end
%hook TTKTabTopEntranceResult
- (NSArray *)children { return FilterTabs(%orig); }
- (void)setChildren:(NSArray *)tabs { %orig(FilterTabs(tabs)); }
%end
%hook TTKFeedTopTabControlConfig
- (NSArray *)topTabList { return FilterTabs(%orig); }
- (void)setTopTabList:(NSArray *)tabs { %orig(FilterTabs(tabs)); }
%end
%end

static BOOL Signature(NSString *className, NSString *selector, const char *expected) {
    Method m=class_getInstanceMethod(NSClassFromString(className),NSSelectorFromString(selector));
    return m && strcmp(method_getTypeEncoding(m),expected)==0;
}
%ctor {
    @autoreleasepool {
        TBLoadPreferences();
        NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (![version isEqual:@"47.1.0"] || ![build isEqual:@"471044"]) { TBLog(@"unsupported app version %@ (%@); hooks disabled",version,build); return; }
        BOOL queue=Signature(@"TTKFeedBaseDataController",@"_loadmoreDataSourceWithArray:requestId:","@32@0:8@16@24") && Signature(@"TTKFeedBaseDataController",@"_refreshDataSourceWithArray:cleanRefresh:requestId:","@36@0:8@16B24@28") && Signature(@"TTKFeedDataOperator",@"p_isFYPType","B16@0:8");
        for (NSString *selector in @[@"updateDataSource:param:",@"addObject:param:"]) queue &= Signature(@"TTKFeedDataOperator",selector,"v32@0:8@16@24");
        queue &= Signature(@"TTKFeedDataOperator",@"insertObject:atIndex:param:","q40@0:8@16q24@32") && Signature(@"TTKFeedDataOperator",@"insertAweme:atIndex:checkAndRemove:checkStartPosition:param:","B52@0:8@16q24B32q36@44") && Signature(@"TTKFeedDataOperator",@"insertObjects:atIndexes:param:","v40@0:8@16@24@32");
        BOOL tabs=YES;
        NSArray *classes=@[@"TTKTabEntranceResult",@"TTKTabTopEntranceResult",@"TTKFeedTopTabControlConfig"];
        NSArray *getters=@[@"topTabs",@"children",@"topTabList"], *setters=@[@"setTopTabs:",@"setChildren:",@"setTopTabList:"];
        for (NSUInteger i=0;i<classes.count;i++) tabs &= Signature(classes[i],getters[i],"@16@0:8") && Signature(classes[i],setters[i],"v24@0:8@16");
        if (queue) { %init(Queue); }
        if (tabs) { %init(Tabs); }
        BOOL hot=Signature(@"AWEHotListDataController",@"_loadmoreDataSourceWithArray:requestId:","@32@0:8@16@24") && Signature(@"AWEHotListDataController",@"_refreshDataSourceWithArray:cleanRefresh:requestId:","@36@0:8@16B24@28") && Signature(@"AWEHotListDataController",@"awe_refreshDataSourceWithArray:cleanRefresh:requestId:","@36@0:8@16B24@28") && Signature(@"AWEHotListDataController",@"transferAwemeListIfNeededWithArray:","@24@0:8@16") && Signature(@"AWEHotListDataController",@"transferAwemeListIfNeededWithArray:pullType:","@32@0:8@16q24") && Signature(@"AWEHotListDataController",@"handleResponseModel:pullSuccess:","v28@0:8@16B24") && Signature(@"AWEHotListDataController",@"handleResponseModel:pullType:pullSuccess:","v36@0:8@16q24B32") && Signature(@"AWEAwemeResponseModel",@"setAwemeList:","v24@0:8@16");
        if (hot) { %init(HotQueue); }
        TBLog(@"active For You controller hooks=%d",hot);
        TBLog(@"loaded 0.2.2; queue=%d tabs=%d",queue,tabs);
    }
}
