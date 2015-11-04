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

@interface SharedStorageManager : NSObject
+ (id)sharedStorage;
@property(retain, nonatomic) NSUserDefaults *userDefaults;
@end


@interface GenericSource : NSObject
@end

@interface MailboxSource : GenericSource
- (id)initWithMailbox:(id)arg1;
@end

@interface MFMailboxUid : NSObject <NSCopying>
@end

@interface MFAccount : NSObject
@property (nonatomic, retain) NSString *username;
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



@interface BBSectionInfo : NSObject
@property (nonatomic, copy) NSString *sectionID;
@property (assign,nonatomic) BOOL enabled;
@property (assign,nonatomic) BOOL suppressFromSettings;
@property (assign,nonatomic) BOOL showsInNotificationCenter;
@property (assign,nonatomic) BOOL showsInLockScreen;
@property (assign,nonatomic) BOOL showsMessagePreview;
@property (assign,nonatomic) BOOL allowsNotifications;
@property (nonatomic) NSUInteger pushSettings;
@property (nonatomic) NSUInteger alertType;
@end

@interface BBDataProviderManager
- (id)dataProviderForSectionID:(id)arg1;
- (id)_configureSectionInfo:(id)arg1 forDataProvider:(id)arg2;
- (void)noteSettingsChanged:(id)arg1 forSectionID:(id)arg2;
@end

@interface BBDataProvider
- (id)sectionIdentifier;
@end

@interface BBRemoteDataProvider : BBDataProvider
- (void)setSectionInfo:(id)arg1;
- (BBSectionInfo *)defaultSectionInfo;
@end

@interface RLNDataProvider : NSObject {
	BBSectionInfo *_defaultSectionInfo;
	NSInteger _pushSettings;
}
- (id)sectionIdentifier;
- (id)defaultSectionInfo;
@end

@interface UNDefaultDataProvider : NSObject {
	BBSectionInfo *_defaultSectionInfo;
	NSInteger _pushSettings;
}
- (id)sectionIdentifier;
- (id)defaultSectionInfo;
@end

@interface BBBulletin : NSObject
// @property(retain, nonatomic) BBContent *content;
// @property(retain, nonatomic) BBSound *sound;
@property(copy, nonatomic) NSString *bulletinID;
@property(copy, nonatomic) NSString *publisherBulletinID;
@property(copy, nonatomic) NSString *recordID;
@property(copy, nonatomic) NSString *sectionID;
@property(copy, nonatomic) NSSet *subsectionIDs;
@property(copy, nonatomic) NSString *section;
@property(copy, nonatomic) NSString *message;
@property(copy, nonatomic) NSString *subtitle;
@property(copy, nonatomic) NSString *title;
@property (nonatomic,retain) NSDictionary *context;
@property(readonly, nonatomic) BOOL ignoresQuietMode;
@end

@interface BBBulletinRequest : BBBulletin
@end
