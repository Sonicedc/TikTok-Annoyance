#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Preferences.h"

@interface TBAnnoyanceSettingsController : UITableViewController
@end
@implementation TBAnnoyanceSettingsController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"TikTok Annoyance";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return TBOptionCount; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Enabled switches hide that content. Refresh For You after changing filters. Reopen TikTok after changing the Shop tab. Posts that match multiple enabled filters stay hidden.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"option"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
    cell.textLabel.text=TBOptionTitle((TBOption)indexPath.row);
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    UISwitch *toggle=[UISwitch new]; toggle.tag=indexPath.row; toggle.on=TBOptionEnabled((TBOption)indexPath.row);
    toggle.accessibilityLabel=cell.textLabel.text;
    [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView=toggle;
    return cell;
}
- (void)changed:(UISwitch *)toggle { TBSetOption((TBOption)toggle.tag,toggle.on); }
@end

static UILabel *FindSettingsLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)view;
        NSString *text=label.text.lowercaseString;
        if ([text isEqual:@"settings and privacy"] || [text isEqual:@"settings & privacy"]) return label;
    }
    for (UIView *child in view.subviews) { UILabel *found=FindSettingsLabel(child); if (found) return found; }
    return nil;
}

// A scroll-content row scoped to TikTok's profile menu controllers. Keeping it
// outside TikTok's private cell model preserves its data source and selection indexes.
@interface TBMenuEntry : NSObject
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,weak) UIScrollView *scroll;
@property(nonatomic,weak) UILabel *settingsLabel;
@property(nonatomic,strong) UIView *entry;
@property(nonatomic,strong) UIView *separator;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIImageView *icon;
@property(nonatomic,strong) UILabel *menuTitle;
@property(nonatomic) CGFloat extraInset;
@property(nonatomic) BOOL observing;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL reported;
- (void)update;
@end
@implementation TBMenuEntry
- (void)dealloc {
    if (_observing) [_scroll removeObserver:self forKeyPath:@"contentSize" context:(__bridge void *)self];
}
- (void)open {
    UIViewController *owner=self.owner;
    if (!owner || owner.presentedViewController) return;
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:[TBAnnoyanceSettingsController new]];
    nav.modalPresentationStyle=UIModalPresentationPageSheet;
    [owner presentViewController:nav animated:YES completion:nil];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == (__bridge void *)self) {
        if (NSThread.isMainThread) [self update];
        else dispatch_async(dispatch_get_main_queue(),^{ [self update]; });
    } else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
- (void)update {
    if (self.updating || !NSThread.isMainThread) return;
    self.updating=YES;
    UILabel *label=FindSettingsLabel(self.owner.view);
    if (label) self.settingsLabel=label;
    else label=self.settingsLabel;
    if (!label || !label.window) { self.updating=NO; return; }
    UIView *row=label;
    UIScrollView *scroll=nil;
    for (UIView *parent=label.superview;parent;parent=parent.superview) {
        if ([parent isKindOfClass:UIScrollView.class]) { scroll=(UIScrollView *)parent; break; }
        if ([parent isKindOfClass:UICollectionViewCell.class] || [parent isKindOfClass:UITableViewCell.class]) row=parent;
        else if (parent.bounds.size.height>=44 && parent.bounds.size.height<=90) row=parent;
    }
    if (!scroll) { self.updating=NO; return; }
    if (self.scroll != scroll) {
        if (self.observing) [self.scroll removeObserver:self forKeyPath:@"contentSize" context:(__bridge void *)self];
        [self.entry removeFromSuperview];
        self.scroll=scroll; self.extraInset=0;
        [scroll addObserver:self forKeyPath:@"contentSize" options:0 context:(__bridge void *)self]; self.observing=YES;
    }
    if (!self.entry) {
        self.entry=[UIView new]; self.separator=[UIView new];
        self.separator.backgroundColor=UIColor.separatorColor;
        [self.entry addSubview:self.separator];
        self.button=[UIButton buttonWithType:UIButtonTypeSystem];
        self.button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        self.menuTitle=[UILabel new]; self.menuTitle.text=@"TikTok Annoyance";
        [self.button addSubview:self.menuTitle];
        [self.button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        self.button.accessibilityLabel=@"TikTok Annoyance";
        [self.entry addSubview:self.button];
        self.icon=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]]];
        self.icon.contentMode=UIViewContentModeScaleAspectFit;
        self.icon.isAccessibilityElement=NO;
        [self.button addSubview:self.icon];
    }
    if (self.entry.superview != scroll) [scroll addSubview:self.entry];
    CGRect rowFrame=[row convertRect:row.bounds toView:scroll];
    CGRect labelFrame=[label convertRect:label.bounds toView:scroll];
    CGFloat width=scroll.bounds.size.width;
    CGFloat top=CGRectGetMaxY(rowFrame)+6;
    CGFloat height=MAX(56,label.font.lineHeight+28)+12;
    self.entry.frame=CGRectMake(0,top,width,height);
    self.separator.frame=CGRectMake(16,0,MAX(0,width-32),1/UIScreen.mainScreen.scale);
    CGFloat left=MAX(52,labelFrame.origin.x);
    self.button.frame=CGRectMake(16,8,MAX(0,width-32),height-8);
    self.menuTitle.frame=CGRectMake(left-16,0,MAX(0,width-left-16),height-8);
    self.icon.frame=CGRectMake(MAX(0,left-52),(height-8-22)/2,22,22);
    self.icon.tintColor=label.textColor ?: UIColor.labelColor;
    self.menuTitle.font=label.font ?: [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.menuTitle.adjustsFontForContentSizeCategory=YES;
    self.menuTitle.textColor=label.textColor ?: UIColor.labelColor;
    // Reserve scrollable space without changing native cell or section counts.
    UIEdgeInsets inset=scroll.contentInset;
    CGFloat originalBottom=MAX(0,inset.bottom-self.extraInset);
    CGFloat needed=MAX(0,CGRectGetMaxY(self.entry.frame)+12-scroll.contentSize.height);
    self.extraInset=needed;
    if (fabs(inset.bottom-(originalBottom+needed))>0.5) { inset.bottom=originalBottom+needed; scroll.contentInset=inset; }
    [scroll bringSubviewToFront:self.entry];
    if (!self.reported) { self.reported=YES; TBReport([NSString stringWithFormat:@"settings entry attached below Settings and privacy in %@",NSStringFromClass(self.owner.class)]); }
    self.updating=NO;
}
@end
static void UpdateMenu(UIViewController *controller) {
    static const void *key=&key;
    if (!NSThread.isMainThread) return;
    TBMenuEntry *entry=objc_getAssociatedObject(controller,key);
    if (!entry) {
        entry=[TBMenuEntry new]; entry.owner=controller;
        objc_setAssociatedObject(controller,key,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [entry update];
}
%group LegacyMenu
%hook TTKProfileMenuViewController
- (void)viewDidLayoutSubviews { %orig; UpdateMenu((id)self); }
- (void)viewDidAppear:(BOOL)animated { %orig; UpdateMenu((id)self); }
%end
%end
%group ProfileSidebar
%hook TBProfileSidebarController
- (void)viewDidLayoutSubviews { %orig; UpdateMenu((id)self); }
- (void)viewDidAppear:(BOOL)animated { %orig; UpdateMenu((id)self); }
%end
%end
%group GeneralSidebar
%hook TBGeneralSidebarController
- (void)viewDidLayoutSubviews { %orig; UpdateMenu((id)self); }
- (void)viewDidAppear:(BOOL)animated { %orig; UpdateMenu((id)self); }
%end
%end
static BOOL MenuClassReady(NSString *name) {
    Class cls=NSClassFromString(name);
    if (!cls || ![cls isSubclassOfClass:UIViewController.class]) return NO;
    Method layout=class_getInstanceMethod(cls,@selector(viewDidLayoutSubviews));
    Method appear=class_getInstanceMethod(cls,@selector(viewDidAppear:));
    return layout && appear && !strcmp(method_getTypeEncoding(layout),"v16@0:8") && !strcmp(method_getTypeEncoding(appear),"v20@0:8B16");
}
%ctor {
    @autoreleasepool {
        if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"47.1.0"] || ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"471044"]) return;
        if (MenuClassReady(@"TTKProfileMenuViewController")) { %init(LegacyMenu); }
        NSString *profile=@"_TtC17TikTokSideBarImpl28ProfileSidebarViewController";
        if (MenuClassReady(profile)) { %init(ProfileSidebar,TBProfileSidebarController=NSClassFromString(profile)); }
        NSString *general=@"_TtC17TikTokSideBarImpl21SidebarViewController";
        if (MenuClassReady(general)) { %init(GeneralSidebar,TBGeneralSidebarController=NSClassFromString(general)); }
        TBReport(@"TikTok Annoyance menu hooks initialized");
    }
}
