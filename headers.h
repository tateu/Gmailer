@interface SpringBoard
@end

@interface SpringBoard (Gmailer)
- (void)gmailerMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
@end

@interface MailAppController : UIApplication
@end

@interface MailAppController (Gmailer)
- (void)gmailerMessageNamed:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
@end

@interface LSResourceProxy : NSObject
@end

@interface LSBundleProxy : LSResourceProxy
@property (nonatomic,readonly) NSDictionary *groupContainerURLs;
@end

@interface LSApplicationProxy : LSBundleProxy
+ (id)applicationProxyForIdentifier:(id)arg1;
@end

@interface SBBackgroundMultitaskingManager :NSObject
+ (id)sharedInstance;
- (BOOL)_launchAppForUpdating:(id)arg1 trigger:(NSUInteger)arg2 pushNotificationUserInfo:(id)arg3 withWatchdoggableCompletion:(/*^block*/id)arg4;
@end

@interface NSUserDefaults (Private)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

@interface PCSimpleTimer : NSObject {
	double _fireTime;
}
- (id)initWithFireDate:(id)arg1 serviceIdentifier:(id)arg2 target:(id)arg3 selector:(SEL)arg4 userInfo:(id)arg5;
- (id)userInfo;
- (void)invalidate;
- (void)scheduleInRunLoop:(id)arg1;
@end


@interface GmailAccountManager : NSObject
- (id)userEmailsForAccounts;
- (NSInteger)fetchOrAssignUniqueIdForEmail:(id)arg1;
@end


@interface GenericSource : NSObject
@end

@interface MailboxSource : GenericSource
- (id)initWithMailbox:(id)arg1;
@end

@interface MFMailboxUid : NSObject <NSCopying>
@end

@interface MFAccount : NSObject
@end

@interface MailAccount : MFAccount
- (MFMailboxUid *)rootMailboxUid;
+ (id)activeAccounts;
+ (id)allMailboxUids;
+ (void)reloadAccounts;
- (id)displayName;
- (void)fetchMailboxList;
- (BOOL)isActive;

+ (id)accountContainingEmailAddress:(id)arg1;
+ (id)existingAccountForUniqueID:(id)arg1;
+ (id)accountWithUniqueId:(id)arg1;
+ (id)accountWithPath:(id)arg1;
+ (id)accountWithURLString:(id)arg1;

- (id)defaultEmailAddress;
- (id)fromEmailAddresses;
- (id)firstEmailAddress;
- (id)path;
- (id)primaryMailboxUid;
- (id)uniqueIdForPersistentConnection;
- (BOOL)canFetch;
@end

@interface AutoFetchController : NSObject
+ (id)sharedController;
- (void)fetchNow:(int)arg1;
- (void)fetchNow:(int)arg1 withAccounts:(id)arg2;
- (void)fetchNow:(int)arg1 withSources:(id)arg2;
@end
